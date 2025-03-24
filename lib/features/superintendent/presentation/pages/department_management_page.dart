import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'student_management_page.dart';
import 'faculty_management_page.dart';
import 'course_management_page.dart';

class DepartmentManagementPage extends ConsumerStatefulWidget {
  const DepartmentManagementPage({super.key});

  @override
  ConsumerState<DepartmentManagementPage> createState() =>
      _DepartmentManagementPageState();
}

class _DepartmentManagementPageState
    extends ConsumerState<DepartmentManagementPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> filteredDepartments = [];
  bool isLoading = true;
  bool isInitializing = true;
  String searchQuery = '';

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Current section for sidebar
  String _currentSection = 'all';

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start animations
    _fadeInController.forward();
    _slideController.forward();

    loadDepartments();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> loadDepartments() async {
    setState(() {
      isLoading = true;
      isInitializing = true;
    });

    try {
      developer.log('Loading departments...');

      final departmentsResponse =
          await Supabase.instance.client.from('departments').select('''
            *,
            courses:course(course_code),
            students:student(student_reg_no),
            faculty:faculty(faculty_id)
          ''').order('dept_id');

      developer.log('Loaded ${departmentsResponse.length} departments');

      setState(() {
        departments = List<Map<String, dynamic>>.from(departmentsResponse);
        filterDepartments();
        isLoading = false;
        isInitializing = false;
      });
    } catch (error) {
      developer.log('Error loading departments: $error', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load departments: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        isLoading = false;
        isInitializing = false;
      });
    }
  }

  void filterDepartments() {
    if (searchQuery.isEmpty) {
      setState(() {
        filteredDepartments = departments;
      });
      return;
    }

    final lowercaseQuery = searchQuery.toLowerCase();

    setState(() {
      filteredDepartments = departments.where((department) {
        return department['dept_name']
                .toString()
                .toLowerCase()
                .contains(lowercaseQuery) ||
            department['dept_id']
                .toString()
                .toLowerCase()
                .contains(lowercaseQuery);
      }).toList();
    });
  }

  Future<void> _addEditDepartment({Map<String, dynamic>? department}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => DepartmentDialog(department: department),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        if (department == null) {
          // Add new department
          await Supabase.instance.client.from('departments').insert(result);
        } else {
          // Update existing department
          await Supabase.instance.client
              .from('departments')
              .update(result)
              .eq('dept_id', department['dept_id']);
        }
        loadDepartments();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                department == null
                    ? 'Failed to add department'
                    : 'Failed to update department',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteDepartment(String deptId) async {
    // First check if department has any courses or students
    try {
      final coursesCount = await Supabase.instance.client
          .from('course')
          .select('course_code')
          .eq('dept_id', deptId);

      final studentsCount = await Supabase.instance.client
          .from('student')
          .select('student_reg_no')
          .eq('dept_id', deptId);

      if (coursesCount.isNotEmpty || studentsCount.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Cannot delete department that has courses or students assigned'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Delete'),
          content:
              const Text('Are you sure you want to delete this department?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        setState(() => isLoading = true);
        await Supabase.instance.client
            .from('departments')
            .delete()
            .eq('dept_id', deptId);
        loadDepartments();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete department'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _showDepartmentInfo(Map<String, dynamic> department) {
    final courses = (department['courses'] ?? []) as List;
    final students = (department['students'] ?? []) as List;
    final faculty = (department['faculty'] ?? []) as List;
    final createdAt = DateTime.parse(department['created_at']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(24),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    department['dept_name'],
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.pop(context);
                    _addEditDepartment(department: department);
                  },
                  tooltip: 'Edit Department',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange,
                    ),
                  ),
                  child: Text(
                    department['dept_id'],
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Created ${_formatDate(createdAt)}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Statistics Row
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      icon: Icons.people,
                      value: students.length.toString(),
                      label: 'Students',
                    ),
                    VerticalDivider(color: Colors.grey[300], width: 32),
                    _buildStatColumn(
                      icon: Icons.school,
                      value: faculty.length.toString(),
                      label: 'Faculty',
                    ),
                    VerticalDivider(color: Colors.grey[300], width: 32),
                    _buildStatColumn(
                      icon: Icons.book,
                      value: courses.length.toString(),
                      label: 'Courses',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Navigation Cards
            _buildInfoCard(
              icon: Icons.people,
              title: 'Manage Students',
              count: students.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StudentManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.school,
              title: 'Manage Faculty',
              count: faculty.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FacultyManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.book,
              title: 'Manage Courses',
              count: courses.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CourseManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Colors.grey[700]),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} years ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.grey[700]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? title.toLowerCase().substring(0, title.length - 1) : title.toLowerCase()}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final theme = Theme.of(context);
    final isWeb = kIsWeb;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: Text(
                'Department Management',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              actions: [
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addEditDepartment(),
                ),
              ],
            )
          : null,
      body: isInitializing
          ? _buildLoadingScreen()
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.orange.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSmallScreen) _buildSidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          // Top bar for non-small screens with Add Department button
                          if (!isSmallScreen)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isLoading)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  FilledButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Department'),
                                    onPressed: () => _addEditDepartment(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.orange.shade700,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: loadDepartments,
                              child: CustomScrollView(
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!isSmallScreen)
                                            _buildHeaderSection(),
                                          if (isSmallScreen)
                                            const SizedBox(height: 16),
                                          if (isSmallScreen)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 16),
                                              child: TextField(
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'Search departments...',
                                                  prefixIcon:
                                                      const Icon(Icons.search),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 12),
                                                ),
                                                onChanged: (value) {
                                                  setState(() {
                                                    searchQuery = value;
                                                    filterDepartments();
                                                  });
                                                },
                                              ),
                                            ),
                                          const SizedBox(height: 16),
                                          if (isLoading)
                                            Center(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(16.0),
                                                child:
                                                    CircularProgressIndicator(
                                                  color: Colors.orange.shade700,
                                                ),
                                              ),
                                            )
                                          else
                                            _buildDepartmentGrid(isSmallScreen),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      drawer: isSmallScreen
          ? Drawer(
              child: _buildSidebar(),
            )
          : null,
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.orange.shade700,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading departments...',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.business,
                      size: 32,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Departments',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search departments...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                    filterDepartments();
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSidebarItem(
                      'all',
                      'All Departments',
                      Icons.business_outlined,
                      onTap: () {
                        setState(() {
                          _currentSection = 'all';
                          searchQuery = '';
                          filterDepartments();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.dashboard),
                label: const Text('Return to Dashboard'),
                onPressed: () {
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    String id,
    String title,
    IconData icon, {
    required VoidCallback onTap,
    bool isMultiSelect = false,
    bool isSelected = false,
  }) {
    final isActive = _currentSection == id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isActive || isSelected
                  ? Colors.orange.shade50
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive || isSelected
                      ? Colors.orange.shade700
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: isActive || isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isActive || isSelected
                          ? Colors.orange.shade700
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
                if (isMultiSelect)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? Colors.orange.shade700
                          : Colors.grey.shade200,
                      border: Border.all(
                        color: isSelected
                            ? Colors.orange.shade700
                            : Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    searchQuery.isEmpty ? 'All Departments' : 'Search Results',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${filteredDepartments.length} departments',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (searchQuery.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Clear Search'),
                onPressed: () {
                  setState(() {
                    searchQuery = '';
                    filterDepartments();
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentGrid(bool isSmallScreen) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Adapt cross axis count based on available space
    final effectiveWidth = screenWidth - (isSmallScreen ? 0 : 280);
    final crossAxisCount = (effectiveWidth / 320).floor();

    return filteredDepartments.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.business_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No departments found',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                if (searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.search_off),
                      label: const Text('Clear Search'),
                      onPressed: () {
                        setState(() {
                          searchQuery = '';
                          filterDepartments();
                        });
                      },
                    ),
                  ),
              ],
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount.clamp(1, 4),
              childAspectRatio: 1.1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filteredDepartments.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final department = filteredDepartments[index];
              final courses = department['courses'] as List;
              final students = department['students'] as List;
              final faculty = department['faculty'] as List;

              return _buildDepartmentCard(
                  department, courses, students, faculty);
            },
          );
  }

  Widget _buildDepartmentCard(
    Map<String, dynamic> department,
    List courses,
    List students,
    List faculty,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.orange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showDepartmentInfo(department),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Department Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.business,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Department Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          department['dept_name'],
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange,
                            ),
                          ),
                          child: Text(
                            department['dept_id'],
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Menu Button
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      if (courses.isEmpty && students.isEmpty)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        _addEditDepartment(department: department);
                      } else if (value == 'delete') {
                        _deleteDepartment(department['dept_id']);
                      }
                    },
                  ),
                ],
              ),
              const Spacer(),
              // Stats Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.book,
                    value: courses.length.toString(),
                    label: 'Courses',
                  ),
                  _buildStatItem(
                    icon: Icons.school,
                    value: faculty.length.toString(),
                    label: 'Faculty',
                  ),
                  _buildStatItem(
                    icon: Icons.people,
                    value: students.length.toString(),
                    label: 'Students',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class DepartmentDialog extends StatefulWidget {
  final Map<String, dynamic>? department;

  const DepartmentDialog({
    super.key,
    this.department,
  });

  @override
  State<DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<DepartmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.department != null) {
      _idController.text = widget.department!['dept_id'];
      _nameController.text = widget.department!['dept_name'];
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.department != null;

    return AlertDialog(
      title: Text(
        isEditing ? 'Edit Department' : 'Add Department',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _idController,
              decoration: InputDecoration(
                labelText: 'Department ID',
                hintText: 'e.g., CSE, EEE',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              readOnly: isEditing, // ID can't be changed after creation
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a department ID';
                }
                if (!isEditing && value.length > 10) {
                  return 'ID must be 10 characters or less';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Department Name',
                hintText: 'e.g., Computer Science and Engineering',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a department name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(),
          ),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                {
                  'dept_id': _idController.text.trim(),
                  'dept_name': _nameController.text.trim(),
                },
              );
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
          ),
          child: Text(
            isEditing ? 'Update' : 'Add',
            style: GoogleFonts.poppins(),
          ),
        ),
      ],
    );
  }
}
