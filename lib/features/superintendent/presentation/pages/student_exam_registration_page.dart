import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class StudentExamRegistrationPage extends ConsumerStatefulWidget {
  const StudentExamRegistrationPage({super.key});

  @override
  ConsumerState<StudentExamRegistrationPage> createState() =>
      _StudentExamRegistrationPageState();
}

class _StudentExamRegistrationPageState
    extends ConsumerState<StudentExamRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _selectedStudent;
  String? _selectedCourse;
  bool _isRegular = true;

  // Lists for all data
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _courses = [];

  // Lists for filtered data
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _filteredCourses = [];

  // Filter controllers
  final _studentSearchController = TextEditingController();
  final _courseSearchController = TextEditingController();
  String? _selectedDepartment;
  int? _selectedSemester;
  List<String> _departments = [];
  List<int> _semesters = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _studentSearchController.dispose();
    _courseSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load students
      final studentsResponse = await Supabase.instance.client
          .from('student')
          .select('student_reg_no, student_name, dept_id, semester')
          .order('student_reg_no');

      // Load courses
      final coursesResponse = await Supabase.instance.client
          .from('course')
          .select('course_code, course_name, dept_id, credit')
          .order('course_code');

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsResponse);
          _courses = List<Map<String, dynamic>>.from(coursesResponse);

          // Extract unique departments and semesters
          _departments = _students
              .map((s) => s['dept_id'].toString())
              .toSet()
              .toList()
            ..sort();
          _semesters = _students
              .map((s) => s['semester'] as int)
              .toSet()
              .toList()
            ..sort();

          // Initialize filtered lists
          _filteredStudents = _students;
          _filteredCourses = _courses;
          _isLoading = false;
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
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((student) {
        // Apply search filter
        final searchMatch = _studentSearchController.text.isEmpty ||
            student['student_name']
                .toString()
                .toLowerCase()
                .contains(_studentSearchController.text.toLowerCase()) ||
            student['student_reg_no']
                .toString()
                .toLowerCase()
                .contains(_studentSearchController.text.toLowerCase());

        // Apply department filter
        final departmentMatch = _selectedDepartment == null ||
            student['dept_id'] == _selectedDepartment;

        // Apply semester filter
        final semesterMatch = _selectedSemester == null ||
            student['semester'] == _selectedSemester;

        return searchMatch && departmentMatch && semesterMatch;
      }).toList();
    });
  }

  void _filterCourses() {
    setState(() {
      _filteredCourses = _courses.where((course) {
        // Apply search filter
        final searchMatch = _courseSearchController.text.isEmpty ||
            course['course_name']
                .toString()
                .toLowerCase()
                .contains(_courseSearchController.text.toLowerCase()) ||
            course['course_code']
                .toString()
                .toLowerCase()
                .contains(_courseSearchController.text.toLowerCase());

        // Apply department filter if selected
        final departmentMatch = _selectedDepartment == null ||
            course['dept_id'] == _selectedDepartment;

        return searchMatch && departmentMatch;
      }).toList();
    });
  }

  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudent == null || _selectedCourse == null) return;

    setState(() => _isLoading = true);
    try {
      // Check if registration already exists
      final existingRegistration = await Supabase.instance.client
          .from('registered_students')
          .select()
          .eq('student_reg_no', _selectedStudent as Object)
          .eq('course_code', _selectedCourse as Object)
          .maybeSingle();

      if (existingRegistration != null) {
        throw Exception('Student is already registered for this course');
      }

      // Register student for exam
      await Supabase.instance.client.from('registered_students').insert({
        'student_reg_no': _selectedStudent,
        'course_code': _selectedCourse,
        'is_reguler': _isRegular,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student registered successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Clear form
        setState(() {
          _selectedStudent = null;
          _selectedCourse = null;
          _isRegular = true;
          _studentSearchController.clear();
          _courseSearchController.clear();
          _selectedDepartment = null;
          _selectedSemester = null;
          _filterStudents();
          _filterCourses();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error registering student: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Student for Exam'),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Theme.of(context).colorScheme.primary,
                size: 50,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Student Filters
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Student Selection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _studentSearchController,
                              decoration: InputDecoration(
                                labelText: 'Search Student',
                                hintText:
                                    'Search by name or registration number',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) => _filterStudents(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedDepartment,
                                    decoration: const InputDecoration(
                                      labelText: 'Department',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('All Departments'),
                                      ),
                                      ..._departments
                                          .map((dept) => DropdownMenuItem(
                                                value: dept,
                                                child: Text(dept),
                                              )),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedDepartment = value;
                                        _filterStudents();
                                        _filterCourses();
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _selectedSemester,
                                    decoration: const InputDecoration(
                                      labelText: 'Semester',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('All Semesters'),
                                      ),
                                      ..._semesters
                                          .map((sem) => DropdownMenuItem(
                                                value: sem,
                                                child: Text(sem.toString()),
                                              )),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedSemester = value;
                                        _filterStudents();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedStudent,
                              decoration: InputDecoration(
                                labelText: 'Select Student',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: _filteredStudents
                                  .map<DropdownMenuItem<String>>((student) {
                                return DropdownMenuItem<String>(
                                  value: student['student_reg_no'] as String,
                                  child: Text(
                                    '${student['student_reg_no']} - ${student['student_name']} (${student['dept_id']} - Sem ${student['semester']})',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedStudent = value);
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select a student';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Course Filters
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Course Selection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _courseSearchController,
                              decoration: InputDecoration(
                                labelText: 'Search Course',
                                hintText: 'Search by name or code',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) => _filterCourses(),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedCourse,
                              decoration: InputDecoration(
                                labelText: 'Select Course',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: _filteredCourses
                                  .map<DropdownMenuItem<String>>((course) {
                                return DropdownMenuItem<String>(
                                  value: course['course_code'] as String,
                                  child: Text(
                                    '${course['course_code']} - ${course['course_name']} (${course['dept_id']} - ${course['credit']} credits)',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedCourse = value);
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select a course';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Regular/Non-Regular Selection
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SwitchListTile(
                          title: const Text('Regular Student'),
                          subtitle: Text(
                            _isRegular ? 'Regular Exam' : 'Backlog Exam',
                            style: TextStyle(
                              color: _isRegular ? Colors.green : Colors.orange,
                            ),
                          ),
                          value: _isRegular,
                          onChanged: (value) {
                            setState(() => _isRegular = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Submit Button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _registerStudent,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? LoadingAnimationWidget.staggeredDotsWave(
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              )
                            : const Text(
                                'Register for Exam',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
