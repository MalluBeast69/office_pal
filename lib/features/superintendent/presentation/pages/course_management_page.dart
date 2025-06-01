import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'dart:developer' as developer;

class CourseManagementPage extends ConsumerStatefulWidget {
  final String? initialDepartment;

  const CourseManagementPage({
    super.key,
    this.initialDepartment,
  });

  @override
  ConsumerState<CourseManagementPage> createState() =>
      _CourseManagementPageState();
}

class _CourseManagementPageState extends ConsumerState<CourseManagementPage>
    with TickerProviderStateMixin {
  bool isLoading = false;
  List<Map<String, dynamic>> courses = [];
  List<Map<String, dynamic>> filteredCourses = [];
  List<String> departments = [];

  // Multiple selections
  Set<String> selectedDepartments = {};
  Set<String> selectedCourseTypes = {};
  Set<String> selectedSemesters = {};

  String searchQuery = '';
  final _formKey = GlobalKey<FormState>();
  final _courseCodeController = TextEditingController();
  final _courseNameController = TextEditingController();
  final _deptIdController = TextEditingController();
  final _creditController = TextEditingController();
  final _semesterController = TextEditingController();

  final List<String> courseTypes = ['major', 'minor1', 'minor2', 'common'];
  final List<String> semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Current section for sidebar
  String _currentSection = 'all';

  // Scroll controllers for better performance
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();

  // Clear filters method
  void _clearFilters() {
    setState(() {
      selectedDepartments.clear();
      selectedCourseTypes.clear();
      selectedSemesters.clear();
      searchQuery = '';
      _currentSection = 'all';
      filterCourses();
    });
  }

  @override
  void initState() {
    super.initState();

    // Initialize with initial department if provided
    if (widget.initialDepartment != null &&
        widget.initialDepartment!.isNotEmpty) {
      selectedDepartments.add(widget.initialDepartment!);
    }

    // Initialize animations for better UX
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

    // Load data
    _loadCourses();
  }

  @override
  void dispose() {
    _courseCodeController.dispose();
    _courseNameController.dispose();
    _deptIdController.dispose();
    _creditController.dispose();
    _semesterController.dispose();
    _fadeInController.dispose();
    _slideController.dispose();
    _mainScrollController.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  void filterCourses() {
    setState(() {
      if (searchQuery.isEmpty &&
          selectedDepartments.isEmpty &&
          selectedCourseTypes.isEmpty &&
          selectedSemesters.isEmpty) {
        filteredCourses = List.from(courses);
        return;
      }

      filteredCourses = courses.where((course) {
        // Search query filter
        bool matchesSearch = searchQuery.isEmpty ||
            course['course_code']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            course['course_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());

        // Department filter
        bool matchesDepartment = selectedDepartments.isEmpty ||
            selectedDepartments.contains(course['dept_id']);

        // Course type filter
        bool matchesCourseType = selectedCourseTypes.isEmpty ||
            selectedCourseTypes.contains(course['course_type']);

        // Semester filter
        bool matchesSemester = selectedSemesters.isEmpty ||
            selectedSemesters.contains(course['semester'].toString());

        return matchesSearch &&
            matchesDepartment &&
            matchesCourseType &&
            matchesSemester;
      }).toList();
    });
  }

  Future<void> _loadCourses() async {
    setState(() => isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('course')
          .select()
          .order('course_code');

      final departmentsResponse = await Supabase.instance.client
          .from('departments')
          .select()
          .order('dept_name');

      if (mounted) {
        setState(() {
          courses = List<Map<String, dynamic>>.from(response);
          departments = List<Map<String, dynamic>>.from(departmentsResponse)
              .map((dept) => dept['dept_id'].toString())
              .toSet()
              .toList();

          // If initialDepartment is set but not in departments list, add it
          if (selectedDepartments.isNotEmpty) {
            for (final dept in selectedDepartments) {
              if (!departments.contains(dept)) {
                departments.add(dept);
              }
            }
            departments.sort();
          }

          filteredCourses = List.from(courses);
          isLoading = false;
          filterCourses();
        });
      }
    } catch (error) {
      developer.log('Error loading courses: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading courses: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _showAddEditCourseDialog([Map<String, dynamic>? course]) {
    final bool isEditing = course != null;
    String? selectedCourseType;

    if (isEditing) {
      _courseCodeController.text = course['course_code'];
      _courseNameController.text = course['course_name'];
      _deptIdController.text = course['dept_id'];
      _creditController.text = course['credit'].toString();
      _semesterController.text = course['semester']?.toString() ?? '1';
      selectedCourseType = course['course_type'];
    } else {
      _clearForm();
      // Set department if we have a filter active
      if (selectedDepartments.length == 1) {
        _deptIdController.text = selectedDepartments.first;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(
            isEditing ? 'Edit Course' : 'Add New Course',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
          content: SizedBox(
            width: 400,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isEditing)
                    DropdownButtonFormField<String>(
                      value: departments.contains(_deptIdController.text)
                          ? _deptIdController.text
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      items: [
                        ...departments.map((dept) => DropdownMenuItem(
                              value: dept,
                              child: Text(dept),
                            )),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a department';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            _deptIdController.text = value;
                          });
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _courseCodeController,
                    decoration: InputDecoration(
                      labelText: 'Course Code',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    readOnly: isEditing, // Don't allow editing course code
                    style: isEditing ? TextStyle(color: Colors.grey) : null,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter course code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _courseNameController,
                    decoration: InputDecoration(
                      labelText: 'Course Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter course name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _creditController,
                    decoration: InputDecoration(
                      labelText: 'Credits',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter credits';
                      }
                      if (int.tryParse(value) == null ||
                          int.parse(value) <= 0) {
                        return 'Please enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _semesterController,
                    decoration: InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter semester';
                      }
                      if (int.tryParse(value) == null ||
                          int.parse(value) < 1 ||
                          int.parse(value) > 8) {
                        return 'Please enter a valid semester (1-8)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCourseType,
                    decoration: InputDecoration(
                      labelText: 'Course Type',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: courseTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.toUpperCase()),
                            ))
                        .toList(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select course type';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setDialogState(() {
                        selectedCourseType = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(),
              ),
            ),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  if (isEditing) {
                    _updateCourse(course['course_code'], selectedCourseType);
                  } else {
                    _addCourse(selectedCourseType);
                  }
                }
              },
              child: Text(
                isEditing ? 'Update' : 'Add',
                style: GoogleFonts.poppins(),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _clearForm() {
    _courseCodeController.clear();
    _courseNameController.clear();
    _deptIdController.clear();
    _creditController.clear();
    _semesterController.clear();
  }

  Future<void> _addCourse(String? selectedCourseType) async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCourseType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a course type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      // First verify if department exists
      final deptResponse = await Supabase.instance.client
          .from('department')
          .select()
          .eq('dept_id', _deptIdController.text)
          .single();

      if (deptResponse == null) {
        throw Exception('Selected department does not exist');
      }

      // Then add the course
      await Supabase.instance.client.from('course').insert({
        'course_code': _courseCodeController.text,
        'course_name': _courseNameController.text,
        'dept_id': _deptIdController.text,
        'credit': int.parse(_creditController.text),
        'course_type': selectedCourseType,
        'semester': int.parse(_semesterController.text),
      });

      if (mounted) {
        _clearForm();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Course added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCourses();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding course: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _updateCourse(
      String courseCode, String? selectedCourseType) async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCourseType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a course type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await Supabase.instance.client.from('course').update({
        'course_name': _courseNameController.text,
        'dept_id': _deptIdController.text,
        'credit': int.parse(_creditController.text),
        'course_type': selectedCourseType,
        'semester': int.parse(_semesterController.text),
      }).eq('course_code', courseCode);

      if (mounted) {
        _clearForm();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Course updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCourses();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating course: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _deleteCourse(String courseCode) async {
    try {
      await Supabase.instance.client
          .from('course')
          .delete()
          .eq('course_code', courseCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Course deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCourses();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting course: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null, // We don't need the app bar as we have a permanent sidebar
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditCourseDialog(),
        tooltip: 'Add Course',
        child: const Icon(Icons.add),
      ),
      body: FadeTransition(
        opacity: _fadeInAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left sidebar - always visible
              _buildSidebar(),

              // Main content area
              Expanded(
                child: isLoading
                    ? Center(
                        child: LoadingAnimationWidget.staggeredDotsWave(
                          color: Colors.blue,
                          size: 50,
                        ),
                      )
                    : filteredCourses.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 80,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No courses found',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try adjusting your filters or search',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.filter_list_off),
                                  label: const Text('Clear Filters'),
                                ),
                              ],
                            ),
                          )
                        : CustomScrollView(
                            controller: _mainScrollController,
                            slivers: [
                              SliverAppBar(
                                pinned: true,
                                floating: true,
                                automaticallyImplyLeading: false,
                                backgroundColor: Colors.white,
                                elevation: 0,
                                title: Row(
                                  children: [
                                    Text(
                                      'Courses',
                                      style: GoogleFonts.poppins(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${filteredCourses.length} courses',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  if (filteredCourses.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: _clearFilters,
                                      icon: const Icon(Icons.filter_list_off),
                                      label: const Text('Clear Filters'),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () => _showAddEditCourseDialog(),
                                    tooltip: 'Add Course',
                                  ),
                                ],
                              ),
                              // Active filters section - Only show if there are active filters
                              if (selectedDepartments.isNotEmpty ||
                                  selectedCourseTypes.isNotEmpty ||
                                  selectedSemesters.isNotEmpty ||
                                  searchQuery.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Active Filters',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            // Search query filter chip
                                            if (searchQuery.isNotEmpty)
                                              Chip(
                                                label: Text(
                                                  'Search: "$searchQuery"',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16),
                                                onDeleted: () {
                                                  setState(() {
                                                    searchQuery = '';
                                                    filterCourses();
                                                  });
                                                },
                                              ),
                                            // Department filter chips
                                            ...selectedDepartments.map(
                                              (dept) => Chip(
                                                label: Text(
                                                  'Dept: $dept',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16),
                                                onDeleted: () {
                                                  setState(() {
                                                    selectedDepartments
                                                        .remove(dept);
                                                    filterCourses();
                                                  });
                                                },
                                              ),
                                            ),
                                            // Course type filter chips
                                            ...selectedCourseTypes.map(
                                              (type) => Chip(
                                                label: Text(
                                                  'Type: ${type.toUpperCase()}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16),
                                                onDeleted: () {
                                                  setState(() {
                                                    selectedCourseTypes
                                                        .remove(type);
                                                    filterCourses();
                                                  });
                                                },
                                              ),
                                            ),
                                            // Semester filter chips
                                            ...selectedSemesters.map(
                                              (sem) => Chip(
                                                label: Text(
                                                  'Semester: $sem',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16),
                                                onDeleted: () {
                                                  setState(() {
                                                    selectedSemesters
                                                        .remove(sem);
                                                    filterCourses();
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Grid of courses
                              SliverPadding(
                                padding: const EdgeInsets.all(16.0),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 350,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    mainAxisExtent: 180,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (BuildContext context, int index) {
                                      final course = filteredCourses[index];
                                      return _buildCourseCard(course);
                                    },
                                    childCount: filteredCourses.length,
                                  ),
                                ),
                              ),
                              // Bottom padding
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 80),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(1, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top header with back button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Colors.blue.shade700,
                  ),
                  tooltip: 'Back to Dashboard',
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Course Management',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade200),

          // Scrollable content area
          Expanded(
            child: ListView(
              controller: _sidebarScrollController,
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Search courses...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                        filterCourses();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_list_off),
                  label: const Text('Clear Filters'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  'all',
                  'All Courses',
                  Icons.school,
                  onTap: () {
                    setState(() {
                      _currentSection = 'all';
                      selectedDepartments.clear();
                      selectedCourseTypes.clear();
                      selectedSemesters.clear();
                      filterCourses();
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'DEPARTMENTS',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...departments.map((dept) => _buildSidebarItem(
                      'dept_$dept',
                      dept,
                      Icons.business,
                      isMultiSelect: true,
                      isSelected: selectedDepartments.contains(dept),
                      onTap: () {
                        setState(() {
                          _currentSection = 'departments';
                          // Toggle this department in the selection
                          if (selectedDepartments.contains(dept)) {
                            selectedDepartments.remove(dept);
                          } else {
                            selectedDepartments.add(dept);
                          }
                          filterCourses();
                        });
                      },
                    )),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'COURSE TYPES',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...courseTypes.map((type) => _buildSidebarItem(
                      'type_$type',
                      type.toUpperCase(),
                      Icons.category,
                      isMultiSelect: true,
                      isSelected: selectedCourseTypes.contains(type),
                      onTap: () {
                        setState(() {
                          _currentSection = 'types';
                          // Toggle this type in the selection
                          if (selectedCourseTypes.contains(type)) {
                            selectedCourseTypes.remove(type);
                          } else {
                            selectedCourseTypes.add(type);
                          }
                          filterCourses();
                        });
                      },
                    )),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SEMESTERS',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...semesters.map((sem) => _buildSidebarItem(
                      'sem_$sem',
                      'Semester $sem',
                      Icons.calendar_today,
                      isMultiSelect: true,
                      isSelected: selectedSemesters.contains(sem),
                      onTap: () {
                        setState(() {
                          _currentSection = 'semesters';
                          // Toggle this semester in the selection
                          if (selectedSemesters.contains(sem)) {
                            selectedSemesters.remove(sem);
                          } else {
                            selectedSemesters.add(sem);
                          }
                          filterCourses();
                        });
                      },
                    )),
                const SizedBox(height: 30),
              ],
            ),
          ),

          // Fixed "Back to Dashboard" button at the bottom
          Divider(color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.dashboard),
              label: Text(
                'Back to Dashboard',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue.shade700,
                elevation: 0,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
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
    // For All Courses, use the old selection logic
    if (id == 'all') {
      isSelected = _currentSection == id;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                isMultiSelect && isSelected
                    ? Icon(
                        Icons.check_box,
                        size: 20,
                        color: Colors.blue.shade700,
                      )
                    : isMultiSelect
                        ? Icon(
                            Icons.check_box_outline_blank,
                            size: 20,
                            color: Colors.grey.shade600,
                          )
                        : Icon(
                            icon,
                            size: 20,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? Colors.blue.shade700
                          : Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (id.startsWith('dept_') ||
                    id.startsWith('type_') ||
                    id.startsWith('sem_'))
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.shade100
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getCountForFilter(id),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getCountForFilter(String id) {
    if (id == 'all') return courses.length.toString();

    if (id.startsWith('dept_')) {
      final dept = id.substring(5);
      return courses.where((c) => c['dept_id'] == dept).length.toString();
    }

    if (id.startsWith('type_')) {
      final type = id.substring(5);
      return courses.where((c) => c['course_type'] == type).length.toString();
    }

    if (id.startsWith('sem_')) {
      final sem = id.substring(4);
      return courses
          .where((c) => c['semester'].toString() == sem)
          .length
          .toString();
    }

    return '0';
  }

  Color _getCourseTypeColor(String type) {
    switch (type) {
      case 'major':
        return Colors.blue;
      case 'minor1':
        return Colors.purple;
      case 'minor2':
        return Colors.orange;
      case 'common':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildCourseCard(Map<String, dynamic> course) {
    final courseType = course['course_type'] ?? 'major';
    final typeColor = _getCourseTypeColor(courseType);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: typeColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showAddEditCourseDialog(course),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course['course_code'],
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          course['course_name'],
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: ListTile(
                          leading: const Icon(Icons.edit, color: Colors.blue),
                          title: const Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onTap: () {
                            Navigator.pop(context);
                            _showAddEditCourseDialog(course);
                          },
                        ),
                      ),
                      PopupMenuItem(
                        child: ListTile(
                          leading: const Icon(Icons.delete, color: Colors.red),
                          title: const Text('Delete'),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onTap: () {
                            Navigator.pop(context);
                            _showDeleteConfirmation(course);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.shade400,
                      ),
                    ),
                    child: Text(
                      'Sem ${course['semester'] ?? "N/A"}',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[800],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: typeColor,
                      ),
                    ),
                    child: Text(
                      courseType.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: typeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: typeColor,
                      ),
                    ),
                    child: Text(
                      course['dept_id'],
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${course['credit']} credits',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> course) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Course',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${course['course_code']}: ${course['course_name']}"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
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
              Navigator.pop(context);
              _deleteCourse(course['course_code']);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(),
            ),
          ),
        ],
      ),
    );
  }
}
