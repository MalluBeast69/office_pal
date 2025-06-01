import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'dart:developer' as developer;

class FacultyManagementPage extends ConsumerStatefulWidget {
  final String? initialDepartment;

  const FacultyManagementPage({
    super.key,
    this.initialDepartment,
  });

  @override
  ConsumerState<FacultyManagementPage> createState() =>
      _FacultyManagementPageState();
}

class _FacultyManagementPageState extends ConsumerState<FacultyManagementPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> facultyList = [];
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> filteredFacultyList = [];
  bool isLoading = false;
  bool isInitializing = true;

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Filter states
  Set<String> selectedDepartments = {};
  bool? selectedAvailability;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Current section for sidebar
  String _currentSection = 'all';

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

    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fadeInController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      selectedDepartments.clear();
      selectedAvailability = null;
      searchQuery = '';
      _searchController.clear();
      _currentSection = 'all';
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      filteredFacultyList = facultyList.where((faculty) {
        // Department filter - check if any of the selected departments match
        bool matchesDepartment = selectedDepartments.isEmpty ||
            selectedDepartments.contains(faculty['dept_id']);

        // Availability filter
        bool matchesAvailability = selectedAvailability == null ||
            faculty['is_available'] == selectedAvailability;

        // Search query filter
        bool matchesSearch = searchQuery.isEmpty ||
            faculty['faculty_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            faculty['faculty_id']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());

        return matchesDepartment && matchesAvailability && matchesSearch;
      }).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      isInitializing = true;
      facultyList = [];
    });

    try {
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .order('faculty_name');

      final departmentsResponse = await Supabase.instance.client
          .from('departments')
          .select()
          .order('dept_name');

      if (mounted) {
        setState(() {
          facultyList = List<Map<String, dynamic>>.from(facultyResponse);
          departments = List<Map<String, dynamic>>.from(departmentsResponse);

          // If initialDepartment is set but not in departments list, add it
          if (selectedDepartments.isNotEmpty) {
            for (final deptId in selectedDepartments) {
              if (!departments.any((d) => d['dept_id'] == deptId)) {
                // Just use the department ID as name if we can't find it
                departments.add({'dept_id': deptId, 'dept_name': deptId});
              }
            }
          }

          _applyFilters();
          isLoading = false;
          isInitializing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          isLoading = false;
          isInitializing = false;
        });
      }
    }
  }

  Future<void> _addFaculty() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        departments: departments,
        onSave: (newFaculty) async {
          try {
            setState(() => isLoading = true);
            await Supabase.instance.client.from('faculty').insert(newFaculty);

            if (mounted) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Faculty added successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _loadData();
            }
          } catch (error) {
            if (mounted) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Error adding faculty: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() => isLoading = false);
            }
          }
        },
      ),
    );
  }

  Future<void> _editFaculty(Map<String, dynamic> faculty) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        faculty: faculty,
        departments: departments,
        onSave: (updatedFaculty) async {
          try {
            setState(() => isLoading = true);
            await Supabase.instance.client
                .from('faculty')
                .update(updatedFaculty)
                .eq('faculty_id', faculty['faculty_id']);

            if (mounted) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Faculty updated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _loadData();
            }
          } catch (error) {
            if (mounted) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Error updating faculty: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() => isLoading = false);
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleFacultyStatus(Map<String, dynamic> faculty) async {
    setState(() => isLoading = true);
    try {
      await Supabase.instance.client
          .from('faculty')
          .update({'is_available': !faculty['is_available']}).eq(
              'faculty_id', faculty['faculty_id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            faculty['is_available']
                ? 'Faculty marked as unavailable'
                : 'Faculty marked as available',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating faculty status: $error'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _importFromCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        developer.log('CSV file picked');
        final fileBytes = result.files.first.bytes;
        if (fileBytes == null) {
          throw Exception('No file content found');
        }

        final csvString = String.fromCharCodes(fileBytes);
        final rows = csvString.split('\n');
        if (rows.isEmpty) {
          throw Exception('CSV file is empty');
        }

        // Get headers from first row and normalize them
        final headers = rows[0]
            .split(',')
            .map((header) => header.trim().toLowerCase())
            .toList();
        final requiredHeaders = ['faculty_id', 'faculty_name', 'dept_id'];

        // Validate headers
        for (final header in requiredHeaders) {
          if (!headers.contains(header)) {
            throw Exception('Missing required column: $header');
          }
        }

        // Start processing from row 1 (skip headers)
        setState(() => isLoading = true);
        int successCount = 0;
        int errorCount = 0;
        final List<String> errors = [];

        for (int i = 1; i < rows.length; i++) {
          try {
            if (rows[i].trim().isEmpty) continue; // Skip empty rows

            final columns = rows[i].split(',');
            if (columns.length != headers.length) {
              throw Exception('Invalid number of columns');
            }

            final facultyData = {
              'faculty_id': columns[headers.indexOf('faculty_id')].trim(),
              'faculty_name': columns[headers.indexOf('faculty_name')].trim(),
              'dept_id': columns[headers.indexOf('dept_id')].trim(),
              'is_available': true,
            };

            // Validate data
            final facultyId = facultyData['faculty_id'] as String;
            final facultyName = facultyData['faculty_name'] as String;
            final deptId = facultyData['dept_id'] as String;

            if (facultyId.isEmpty) {
              throw Exception('Faculty ID cannot be empty');
            }
            if (facultyName.isEmpty) {
              throw Exception('Faculty name cannot be empty');
            }
            if (deptId.isEmpty) {
              throw Exception('Department ID cannot be empty');
            }

            // Validate department exists
            final deptExists =
                departments.any((d) => d['dept_id'] == facultyData['dept_id']);
            if (!deptExists) {
              throw Exception(
                  'Department ${facultyData['dept_id']} does not exist');
            }

            await Supabase.instance.client.from('faculty').insert(facultyData);
            successCount++;
          } catch (e) {
            errorCount++;
            errors.add('Row ${i + 1}: $e');
            developer.log('Error processing row ${i + 1}: $e');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Import completed: $successCount successful, $errorCount failed',
              ),
              backgroundColor: errorCount == 0 ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 5),
              action: errorCount > 0
                  ? SnackBarAction(
                      label: 'Show Errors',
                      textColor: Colors.white,
                      onPressed: () => _showErrorDialog(errors),
                    )
                  : null,
            ),
          );
          _loadData();
        }
      }
    } catch (error) {
      developer.log('Error importing CSV: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing CSV: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _showErrorDialog(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Errors'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: errors
                .map((error) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ))
                .toList(),
          ),
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final theme = Theme.of(context);
    const isWeb = kIsWeb;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: Text(
                'Faculty Management',
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
                  )
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
                    Colors.blue.shade50,
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
                          if (!isSmallScreen) _buildAppBar(theme, isWeb),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _loadData,
                              child: CustomScrollView(
                                slivers: [
                                  // Only apply animations on first render, not on refreshes
                                  if (isInitializing)
                                    SliverFadeTransition(
                                      opacity: _fadeInAnimation,
                                      sliver: SliverToBoxAdapter(
                                        child: SlideTransition(
                                          position: _slideAnimation,
                                          child: _buildContent(isSmallScreen),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverToBoxAdapter(
                                      child: _buildContent(isSmallScreen),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addFaculty,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade100,
            Colors.blue.shade50,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.blue,
              size: 50,
            ),
            const SizedBox(height: 24),
            Text(
              'Faculty Management',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading faculty data...',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.person_2,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Faculty',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Add Clear Filters button
            if (selectedDepartments.isNotEmpty ||
                selectedAvailability != null ||
                searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear All Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    minimumSize: const Size(double.infinity, 40),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSidebarItem(
                      'all',
                      'All Faculty',
                      Icons.people,
                      onTap: () {
                        setState(() {
                          _currentSection = 'all';
                          _clearFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
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
                          'dept_${dept['dept_id']}',
                          dept['dept_name'],
                          Icons.business,
                          isMultiSelect: true,
                          isSelected:
                              selectedDepartments.contains(dept['dept_id']),
                          onTap: () {
                            setState(() {
                              _currentSection = 'departments';
                              // Toggle this department in the selection
                              if (selectedDepartments
                                  .contains(dept['dept_id'])) {
                                selectedDepartments.remove(dept['dept_id']);
                              } else {
                                selectedDepartments.add(dept['dept_id']);
                              }
                              _applyFilters();
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
                          'AVAILABILITY',
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
                    _buildSidebarItem(
                      'available',
                      'Available',
                      Icons.check_circle_outline,
                      isSelected: selectedAvailability == true,
                      onTap: () {
                        setState(() {
                          _currentSection = 'availability';
                          selectedAvailability =
                              selectedAvailability == true ? null : true;
                          _applyFilters();
                        });
                      },
                    ),
                    _buildSidebarItem(
                      'unavailable',
                      'Unavailable',
                      Icons.cancel_outlined,
                      isSelected: selectedAvailability == false,
                      onTap: () {
                        setState(() {
                          _currentSection = 'availability';
                          selectedAvailability =
                              selectedAvailability == false ? null : false;
                          _applyFilters();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.grey.shade200),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: Icon(
                  Icons.arrow_back,
                  color: Colors.grey.shade600,
                ),
                title: Text(
                  'Back to Dashboard',
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () => Navigator.pop(context),
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
    // For All Faculty, use the old selection logic
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
                if (id.startsWith('dept_'))
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
                      _getCountForDepartment(id.substring(5)),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

  String _getCountForDepartment(String deptId) {
    int count =
        facultyList.where((faculty) => faculty['dept_id'] == deptId).length;
    return count.toString();
  }

  Widget _buildAppBar(ThemeData theme, bool isWeb) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isWeb
            ? Colors.white.withOpacity(0.8)
            : theme.scaffoldBackgroundColor,
        boxShadow: [
          if (!isLoading)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          Text(
            'Faculty Management',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                ),
              ),
            ),
          SizedBox(
            width: 240,
            height: 40,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search faculty...',
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
                  _applyFilters();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSmallScreen) _buildSearchField(),
          if (!isSmallScreen) _buildHeaderSection(),
          const SizedBox(height: 16),
          _buildFilterChips(),
          const SizedBox(height: 16),
          _buildFacultyList(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search faculty...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
            _applyFilters();
          });
        },
      ),
    );
  }

  Widget _buildHeaderSection() {
    // Build title based on active filters
    List<String> filterParts = [];

    if (selectedDepartments.isNotEmpty) {
      if (selectedDepartments.length == 1) {
        final dept = departments.firstWhere(
          (d) => d['dept_id'] == selectedDepartments.first,
          orElse: () => {'dept_name': selectedDepartments.first},
        );
        filterParts.add('Department: ${dept['dept_name']}');
      } else {
        filterParts.add('${selectedDepartments.length} Departments');
      }
    }

    if (selectedAvailability != null) {
      filterParts.add(selectedAvailability! ? 'Available' : 'Unavailable');
    }

    String title =
        filterParts.isNotEmpty ? filterParts.join(', ') : 'All Faculty';

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
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${filteredFacultyList.length} faculty members',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import CSV'),
                  onPressed: _importFromCsv,
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
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Faculty'),
                  onPressed: _addFaculty,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
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
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Department chips
        ...selectedDepartments.map((deptId) {
          final dept = departments.firstWhere(
            (d) => d['dept_id'] == deptId,
            orElse: () => {'dept_name': deptId},
          );

          return FilterChip(
            label: Text('Dept: ${dept['dept_name']}'),
            onSelected: (_) {
              setState(() {
                selectedDepartments.remove(deptId);
                _applyFilters();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedDepartments.remove(deptId);
                _applyFilters();
              });
            },
          );
        }),

        // Availability chip
        if (selectedAvailability != null)
          FilterChip(
            label: Text(
                'Status: ${selectedAvailability! ? 'Available' : 'Unavailable'}'),
            onSelected: (_) {
              setState(() {
                selectedAvailability = null;
                _applyFilters();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedAvailability = null;
                _applyFilters();
              });
            },
          ),

        // Search query chip
        if (searchQuery.isNotEmpty)
          FilterChip(
            label: Text('Search: $searchQuery'),
            onSelected: (_) {
              setState(() {
                searchQuery = '';
                _searchController.clear();
                _applyFilters();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                searchQuery = '';
                _searchController.clear();
                _applyFilters();
              });
            },
          ),

        // Clear all button
        if (selectedDepartments.isNotEmpty ||
            selectedAvailability != null ||
            searchQuery.isNotEmpty)
          ActionChip(
            label: const Text('Clear All'),
            onPressed: _clearFilters,
            avatar: const Icon(Icons.clear_all, size: 18),
            backgroundColor: Colors.red.shade50,
            labelStyle: TextStyle(color: Colors.red.shade700),
          ),
      ],
    );
  }

  Widget _buildFacultyList() {
    if (filteredFacultyList.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_off,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No faculty members found',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try clearing some filters or add a new faculty member',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 1.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: filteredFacultyList.length,
      itemBuilder: (context, index) {
        final faculty = filteredFacultyList[index];
        final department = departments.firstWhere(
          (d) => d['dept_id'] == faculty['dept_id'],
          orElse: () => {'dept_name': 'Unknown'},
        );

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () => _editFaculty(faculty),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        radius: 24,
                        child: Text(
                          faculty['faculty_name']
                              .toString()
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              faculty['faculty_name'],
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'ID: ${faculty['faculty_id']}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: Colors.blue.shade700,
                        ),
                        onPressed: () => _editFaculty(faculty),
                        tooltip: 'Edit Faculty',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.business,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    department['dept_name'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: faculty['is_available'] == true
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: faculty['is_available'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              faculty['is_available'] == true
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 14,
                              color: faculty['is_available'] == true
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              faculty['is_available'] == true
                                  ? 'Available'
                                  : 'Unavailable',
                              style: GoogleFonts.poppins(
                                color: faculty['is_available'] == true
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _toggleFacultyStatus(faculty),
                      icon: Icon(
                        faculty['is_available'] == true
                            ? Icons.cancel
                            : Icons.check_circle,
                        size: 18,
                      ),
                      label: Text(
                        faculty['is_available'] == true
                            ? 'Mark Unavailable'
                            : 'Mark Available',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: faculty['is_available'] == true
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FacultyDialog extends StatefulWidget {
  final Map<String, dynamic>? faculty;
  final List<Map<String, dynamic>> departments;
  final Function(Map<String, dynamic>) onSave;

  const FacultyDialog({
    super.key,
    this.faculty,
    required this.departments,
    required this.onSave,
  });

  @override
  State<FacultyDialog> createState() => _FacultyDialogState();
}

class _FacultyDialogState extends State<FacultyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDepartment;
  bool _isAvailable = true;

  @override
  void initState() {
    super.initState();
    if (widget.faculty != null) {
      _idController.text = widget.faculty!['faculty_id'];
      _nameController.text = widget.faculty!['faculty_name'];
      _selectedDepartment = widget.faculty!['dept_id'];
      _isAvailable = widget.faculty!['is_available'] ?? true;
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
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Dialog(
      child: Container(
        width: isSmallScreen ? screenSize.width * 0.9 : 500,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.faculty == null ? 'Add Faculty' : 'Edit Faculty',
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Faculty ID',
                  border: OutlineInputBorder(),
                ),
                enabled: widget.faculty == null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter faculty ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Faculty Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter faculty name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: widget.departments.map((dept) {
                  return DropdownMenuItem<String>(
                    value: dept['dept_id'],
                    child: Text(dept['dept_name']),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() => _selectedDepartment = value);
                },
              ),
              const SizedBox(height: 16),
              // Availability Switch
              SwitchListTile(
                title: const Text('Available'),
                value: _isAvailable,
                onChanged: (value) {
                  setState(() => _isAvailable = value);
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSave({
                          'faculty_id': _idController.text,
                          'faculty_name': _nameController.text,
                          'dept_id': _selectedDepartment,
                          'is_available': _isAvailable,
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
