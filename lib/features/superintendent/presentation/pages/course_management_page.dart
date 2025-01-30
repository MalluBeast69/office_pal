import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class _CourseManagementPageState extends ConsumerState<CourseManagementPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> courses = [];
  List<Map<String, dynamic>> filteredCourses = [];
  List<String> departments = [];
  String? selectedDepartment;
  String? selectedCourseType;
  String? selectedSemester;
  final _formKey = GlobalKey<FormState>();
  final _courseCodeController = TextEditingController();
  final _courseNameController = TextEditingController();
  final _deptIdController = TextEditingController();
  final _creditController = TextEditingController();
  final _semesterController = TextEditingController();

  final List<String> courseTypes = ['major', 'minor1', 'minor2', 'common'];
  final List<String> semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];

  @override
  void initState() {
    super.initState();
    selectedDepartment = widget.initialDepartment;
    _loadCourses();
  }

  @override
  void dispose() {
    _courseCodeController.dispose();
    _courseNameController.dispose();
    _deptIdController.dispose();
    _creditController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      filteredCourses = courses.where((course) {
        bool matchesDepartment = selectedDepartment == null ||
            course['dept_id'] == selectedDepartment;
        bool matchesCourseType = selectedCourseType == null ||
            course['course_type'] == selectedCourseType;
        bool matchesSemester = selectedSemester == null ||
            course['semester'].toString() == selectedSemester;
        return matchesDepartment && matchesCourseType && matchesSemester;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      selectedDepartment = null;
      selectedCourseType = null;
      selectedSemester = null;
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
          filteredCourses = List.from(courses);
          isLoading = false;
          _applyFilters();
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
      _semesterController.text = course['semester']?.toString() ?? '1';
      selectedCourseType = course['course_type'];
    } else {
      _clearForm();
    }

    // Function to generate course code
    void generateCourseCode(String deptId) async {
      if (!isEditing) {
        try {
          // Get the count of existing courses for this department
          final response = await Supabase.instance.client
              .from('course')
              .select('course_code')
              .eq('dept_id', deptId);

          final existingCourses = List<Map<String, dynamic>>.from(response);
          final courseCount = existingCourses.length + 1;

          // Generate code: DEPT + Number (e.g., CSE101)
          final newCode = '$deptId${courseCount.toString().padLeft(3, '0')}';
          _courseCodeController.text = newCode;
        } catch (error) {
          developer.log('Error generating course code: $error');
        }
      }
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
              if (!isEditing)
                DropdownButtonFormField<String>(
                  value: departments.contains(selectedDepartment)
                      ? selectedDepartment
                      : null,
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
                    if (value != null) {
                      setState(() {
                        selectedDepartment = value;
                        generateCourseCode(value);
                      });
                    }
                  },
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _courseCodeController,
                decoration: const InputDecoration(
                  labelText: 'Course Code',
                  border: OutlineInputBorder(),
                ),
                enabled: false,
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
                decoration: const InputDecoration(
                  labelText: 'Course Name',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Credits',
                  border: OutlineInputBorder(),
                ),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _semesterController,
                decoration: const InputDecoration(
                  labelText: 'Semester',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Course Type',
                  border: OutlineInputBorder(),
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
    _semesterController.clear();
    selectedCourseType = null;
  }

  Future<void> _addCourse() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCourseType == null) return;

    setState(() => isLoading = true);
    try {
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
    if (selectedCourseType == null) return;

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
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount =
        (screenWidth / 280).floor(); // Reduced from 320 to 280 for more columns

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
                            value: departments.contains(selectedDepartment)
                                ? selectedDepartment
                                : null,
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
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedSemester,
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Semesters'),
                        ),
                        ...semesters.map((sem) => DropdownMenuItem(
                              value: sem,
                              child: Text('Semester $sem'),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedSemester = value;
                          _applyFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Reset Filters'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Course count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Showing ${filteredCourses.length} courses',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Courses grid
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredCourses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.book_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No courses found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 1.5,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filteredCourses.length,
                        itemBuilder: (context, index) {
                          final course = filteredCourses[index];
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                course['course_code'],
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                course['course_name'],
                                                style: TextStyle(
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
                                                leading: const Icon(Icons.edit,
                                                    color: Colors.blue),
                                                title: const Text('Edit'),
                                                contentPadding: EdgeInsets.zero,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _showAddEditCourseDialog(
                                                      course);
                                                },
                                              ),
                                            ),
                                            PopupMenuItem(
                                              child: ListTile(
                                                leading: const Icon(
                                                    Icons.delete,
                                                    color: Colors.red),
                                                title: const Text('Delete'),
                                                contentPadding: EdgeInsets.zero,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                          'Delete Course'),
                                                      content: Text(
                                                          'Are you sure you want to delete ${course['course_code']}?'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context),
                                                          child: const Text(
                                                              'Cancel'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () {
                                                            Navigator.pop(
                                                                context);
                                                            _deleteCourse(course[
                                                                'course_code']);
                                                          },
                                                          style: FilledButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                          child: const Text(
                                                              'Delete'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                          child: Text(
                                            'Sem ${course['semester'] ?? "N/A"}',
                                            style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: typeColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: typeColor,
                                            ),
                                          ),
                                          child: Text(
                                            courseType.toUpperCase(),
                                            style: TextStyle(
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
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: typeColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: typeColor,
                                            ),
                                          ),
                                          child: Text(
                                            course['dept_id'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${course['credit']} credits',
                                              style: const TextStyle(
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
