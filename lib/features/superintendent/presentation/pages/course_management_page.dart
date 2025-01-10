import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class CourseManagementPage extends ConsumerStatefulWidget {
  const CourseManagementPage({super.key});

  @override
  ConsumerState<CourseManagementPage> createState() =>
      _CourseManagementPageState();
}

class _CourseManagementPageState extends ConsumerState<CourseManagementPage> {
  List<Map<String, dynamic>> courses = [];
  List<Map<String, dynamic>> filteredCourses = [];
  bool isLoading = true;
  String searchQuery = '';
  String? selectedDepartment;
  List<String> departments = [];

  @override
  void initState() {
    super.initState();
    loadCourses();
  }

  Future<void> loadCourses() async {
    try {
      developer.log('Loading courses...');

      // Load courses with department details
      final coursesResponse =
          await Supabase.instance.client.from('course').select('''
            course_code,
            course_name,
            dept_id,
            credit,
            departments!inner (
              dept_name
            )
          ''').order('course_code');

      developer.log('Loaded ${coursesResponse.length} courses');

      // Get unique departments
      final departmentsResponse =
          await Supabase.instance.client.from('departments').select();

      setState(() {
        courses = List<Map<String, dynamic>>.from(coursesResponse);
        departments = List<String>.from(
            departmentsResponse.map((d) => d['dept_id'].toString()))
          ..sort();
        filterCourses();
        isLoading = false;
      });
    } catch (error) {
      developer.log('Error loading courses: $error', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load courses: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => isLoading = false);
    }
  }

  void filterCourses() {
    setState(() {
      filteredCourses = courses.where((course) {
        // Check search query
        final matchesSearch = searchQuery.isEmpty ||
            course['course_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            course['course_code']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());

        // Check department
        final matchesDepartment = selectedDepartment == null ||
            course['dept_id'] == selectedDepartment;

        return matchesSearch && matchesDepartment;
      }).toList();
    });
  }

  Future<void> _addEditCourse({Map<String, dynamic>? course}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CourseDialog(
        course: course,
        departments: departments,
      ),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        if (course == null) {
          // Add new course
          await Supabase.instance.client.from('course').insert(result);
        } else {
          // Update existing course
          await Supabase.instance.client
              .from('course')
              .update(result)
              .eq('course_code', course['course_code']);
        }
        loadCourses();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                course == null
                    ? 'Failed to add course'
                    : 'Failed to update course',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteCourse(String courseCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text(
            'Are you sure you want to delete this course? This will also delete all related course registrations.'),
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
      try {
        await Supabase.instance.client
            .from('course')
            .delete()
            .eq('course_code', courseCode);
        loadCourses();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete course'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Course',
            onPressed: () => _addEditCourse(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by course name or code',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    searchQuery = value;
                    filterCourses();
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedDepartment,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Departments'),
                    ),
                    ...departments.map((dept) => DropdownMenuItem(
                          value: dept,
                          child: Text(dept),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedDepartment = value;
                      filterCourses();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredCourses.isEmpty
                    ? const Center(
                        child: Text(
                          'No courses found',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCourses.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final course = filteredCourses[index];
                          final department =
                              course['departments'] as Map<String, dynamic>;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(course['course_name']),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.blue),
                                    ),
                                    child: Text(
                                      '${course['credit']} Credits',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Code: ${course['course_code']}\n'
                                'Department: ${department['dept_name']} (${course['dept_id']})',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit Course',
                                    onPressed: () =>
                                        _addEditCourse(course: course),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    tooltip: 'Delete Course',
                                    onPressed: () =>
                                        _deleteCourse(course['course_code']),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class CourseDialog extends StatefulWidget {
  final Map<String, dynamic>? course;
  final List<String> departments;

  const CourseDialog({
    super.key,
    this.course,
    required this.departments,
  });

  @override
  State<CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<CourseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDepartment;
  final _creditController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.course != null) {
      _codeController.text = widget.course!['course_code'];
      _nameController.text = widget.course!['course_name'];
      _selectedDepartment = widget.course!['dept_id'];
      _creditController.text = widget.course!['credit'].toString();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _creditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.course != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Course' : 'Add Course'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Course Code'),
                enabled: !isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter course code';
                  }
                  if (!RegExp(r'^[A-Z]{4}\d{3}$')
                      .hasMatch(value.toUpperCase())) {
                    return 'Invalid format (e.g., DPCS101)';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Course Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter course name';
                  }
                  return null;
                },
              ),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(labelText: 'Department'),
                items: widget.departments.map((dept) {
                  return DropdownMenuItem(
                    value: dept,
                    child: Text(dept),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null) {
                    return 'Please select a department';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    _selectedDepartment = value;
                  });
                },
              ),
              TextFormField(
                controller: _creditController,
                decoration: const InputDecoration(labelText: 'Credits'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter credits';
                  }
                  final credits = int.tryParse(value);
                  if (credits == null || credits < 1 || credits > 6) {
                    return 'Credits must be between 1 and 6';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'course_code': _codeController.text.trim().toUpperCase(),
                'course_name': _nameController.text.trim(),
                'dept_id': _selectedDepartment,
                'credit': int.parse(_creditController.text.trim()),
              });
            }
          },
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
