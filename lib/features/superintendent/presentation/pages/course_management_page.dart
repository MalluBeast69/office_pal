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
  bool isLoading = false;
  List<Map<String, dynamic>> courses = [];
  List<Map<String, dynamic>> filteredCourses = [];
  List<String> departments = [];
  String? selectedDepartment;
  String? selectedCourseType;
  final _formKey = GlobalKey<FormState>();
  final _courseCodeController = TextEditingController();
  final _courseNameController = TextEditingController();
  final _deptIdController = TextEditingController();
  final _creditController = TextEditingController();

  final List<String> courseTypes = ['major', 'minor1', 'minor2', 'common'];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _courseCodeController.dispose();
    _courseNameController.dispose();
    _deptIdController.dispose();
    _creditController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      filteredCourses = courses.where((course) {
        bool matchesDepartment = selectedDepartment == null ||
            course['dept_id'] == selectedDepartment;
        bool matchesCourseType = selectedCourseType == null ||
            course['course_type'] == selectedCourseType;
        return matchesDepartment && matchesCourseType;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      selectedDepartment = null;
      selectedCourseType = null;
      filteredCourses = List.from(courses);
    });
  }

  Future<void> _loadCourses() async {
    setState(() => isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('course')
          .select()
          .order('course_code');

      if (mounted) {
        setState(() {
          courses = List<Map<String, dynamic>>.from(response);
          filteredCourses = List.from(courses);
          // Extract unique departments
          departments = courses
              .map((course) => course['dept_id'].toString())
              .toSet()
              .toList()
            ..sort();
          isLoading = false;
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
    if (isEditing) {
      _courseCodeController.text = course['course_code'];
      _courseNameController.text = course['course_name'];
      _deptIdController.text = course['dept_id'];
      _creditController.text = course['credit'].toString();
      selectedCourseType = course['course_type'];
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Course' : 'Add New Course'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _courseCodeController,
                decoration: const InputDecoration(labelText: 'Course Code'),
                enabled: !isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter course code';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _courseNameController,
                decoration: const InputDecoration(labelText: 'Course Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter course name';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _deptIdController,
                decoration: const InputDecoration(labelText: 'Department ID'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department ID';
                  }
                  return null;
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
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              DropdownButtonFormField<String>(
                value: selectedCourseType,
                decoration: const InputDecoration(labelText: 'Course Type'),
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
                  setState(() {
                    selectedCourseType = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _clearForm();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (isEditing) {
                _updateCourse(course['course_code']);
              } else {
                _addCourse();
              }
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _courseCodeController.clear();
    _courseNameController.clear();
    _deptIdController.clear();
    _creditController.clear();
    selectedCourseType = null;
  }

  Future<void> _addCourse() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      await Supabase.instance.client.from('course').insert({
        'course_code': _courseCodeController.text,
        'course_name': _courseNameController.text,
        'dept_id': _deptIdController.text,
        'credit': int.parse(_creditController.text),
        'course_type': selectedCourseType,
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
            content: Text('Error adding course: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _updateCourse(String courseCode) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      await Supabase.instance.client.from('course').update({
        'course_name': _courseNameController.text,
        'dept_id': _deptIdController.text,
        'credit': int.parse(_creditController.text),
        'course_type': selectedCourseType,
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
      appBar: AppBar(
        title: const Text('Course Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditCourseDialog(),
            tooltip: 'Add Course',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
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
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCourseType,
                            decoration: const InputDecoration(
                              labelText: 'Course Type',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Types'),
                              ),
                              ...courseTypes.map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.toUpperCase()),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedCourseType = value;
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Courses list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredCourses.isEmpty
                    ? const Center(
                        child: Text(
                          'No courses found',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCourses.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final course = filteredCourses[index];
                          final courseType = course['course_type'] ?? 'major';

                          return Card(
                            child: ListTile(
                              title: Text(course['course_code']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(course['course_name']),
                                  Text('Department: ${course['dept_id']}'),
                                  Text('Credits: ${course['credit']}'),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getCourseTypeColor(courseType)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _getCourseTypeColor(courseType),
                                      ),
                                    ),
                                    child: Text(
                                      courseType.toUpperCase(),
                                      style: TextStyle(
                                        color: _getCourseTypeColor(courseType),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    color: Colors.blue,
                                    onPressed: () =>
                                        _showAddEditCourseDialog(course),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Course'),
                                        content: Text(
                                            'Are you sure you want to delete ${course['course_code']}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteCourse(
                                                  course['course_code']);
                                            },
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
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
}
