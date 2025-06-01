import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class StudentExamRegistrationPage extends ConsumerStatefulWidget {
  final String? studentId;

  const StudentExamRegistrationPage({
    super.key,
    this.studentId,
  });

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

    // If studentId is provided, pre-select it
    if (widget.studentId != null) {
      _selectedStudent = widget.studentId;
    }
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
      // Load students with pagination for better performance
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

          // If studentId is provided, filter and scroll to that student
          if (widget.studentId != null) {
            _selectedStudent = widget.studentId;
            final student = _students.firstWhere(
              (s) => s['student_reg_no'] == widget.studentId,
              orElse: () => <String, dynamic>{},
            );

            if (student.isNotEmpty) {
              _selectedDepartment = student['dept_id'] as String;
              _selectedSemester = student['semester'] as int;
              _filterStudents();
              _filterCourses();
            }
          }

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
        title: const Text(
          'Register Student for Exam',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 2,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
        ],
      ),
      body: Container(
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
        child: _isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Theme.of(context).colorScheme.primary,
                size: 50,
              ),
            )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Responsive layout - use side-by-side for larger screens
                  bool isWideScreen = constraints.maxWidth > 1000;

                  return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                      child: isWideScreen
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: _buildStudentSelection(),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 1,
                                  child: _buildCourseSelection(),
                                ),
                              ],
                            )
                          : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                                _buildStudentSelection(),
                                const SizedBox(height: 16),
                                _buildCourseSelection(),
                              ],
                            ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: !_isLoading
          ? FloatingActionButton.extended(
              onPressed: _selectedStudent != null && _selectedCourse != null
                  ? _registerStudent
                  : null,
              label: const Text('Register for Exam'),
              icon: const Icon(Icons.assignment_turned_in),
              backgroundColor:
                  _selectedStudent != null && _selectedCourse != null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
            )
          : null,
    );
  }

  Widget _buildStudentSelection() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                              'Student Selection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                              ),
                ),
              ],
                            ),
                            const SizedBox(height: 16),

            // Search field
                            TextField(
                              controller: _studentSearchController,
                              decoration: InputDecoration(
                hintText: 'Search by name or reg. number',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
              onChanged: (value) {
                _filterStudents();
              },
                            ),
                            const SizedBox(height: 16),

            // Filters row
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                      labelText: 'Department',
                                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                    value: _selectedDepartment,
                                    items: [
                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('All Departments'),
                                      ),
                      ..._departments.map((dept) => DropdownMenuItem<String>(
                                                value: dept,
                                                child: Text(dept),
                                              )),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedDepartment = value;
                                        _filterStudents();
                                      });
                                    },
                                  ),
                                ),
                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    decoration: const InputDecoration(
                                      labelText: 'Semester',
                                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                    value: _selectedSemester,
                                    items: [
                      const DropdownMenuItem<int>(
                                        value: null,
                                        child: Text('All Semesters'),
                                      ),
                      ..._semesters.map((sem) => DropdownMenuItem<int>(
                                                value: sem,
                            child: Text('Semester $sem'),
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

            // Student list with virtualization for better performance
            SizedBox(
              height: 300,
              child: _filteredStudents.isEmpty
                  ? Center(
                      child: Text(
                        'No students found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final isSelected =
                            _selectedStudent == student['student_reg_no'];

                        return Card(
                          color: isSelected ? Colors.blue.shade50 : null,
                          elevation: isSelected ? 2 : 0,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.blue.shade300
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade200,
                              child: Text(
                                student['student_name']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blue.shade800
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ),
                            title: Text(
                              student['student_name'] as String,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${student['student_reg_no']} | ${student['dept_id']} - Semester ${student['semester']}',
                            ),
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedStudent =
                                    student['student_reg_no'] as String;
                              });
                            },
                          ),
                        );
                      },
                    ),
                            ),
                          ],
                        ),
                      ),
    );
  }

  Widget _buildCourseSelection() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
            Row(
              children: [
                Icon(Icons.book, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                              'Course Selection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                              ),
                ),
              ],
                            ),
                            const SizedBox(height: 16),

            // Search field
                            TextField(
                              controller: _courseSearchController,
                              decoration: InputDecoration(
                hintText: 'Search by course name or code',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                _filterCourses();
              },
            ),
            const SizedBox(height: 16),

            // Course list with virtualization for better performance
            SizedBox(
              height: 300,
              child: _filteredCourses.isEmpty
                  ? Center(
                      child: Text(
                        'No courses found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredCourses.length,
                      itemBuilder: (context, index) {
                        final course = _filteredCourses[index];
                        final isSelected =
                            _selectedCourse == course['course_code'];

                        return Card(
                          color: isSelected ? Colors.blue.shade50 : null,
                          elevation: isSelected ? 2 : 0,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.blue.shade300
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade200,
                              child: Text(
                                course['course_code']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blue.shade800
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ),
                            title: Text(
                              course['course_name'] as String,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          subtitle: Text(
                              '${course['course_code']} | ${course['dept_id']} - ${course['credit']} Credit',
                            ),
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedCourse =
                                    course['course_code'] as String;
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),

            // Registration type toggle
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Text(
                      'Registration Type:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Regular'),
                            icon: Icon(Icons.check_circle_outline),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Backlog'),
                            icon: Icon(Icons.warning_amber_outlined),
                          ),
                        ],
                        selected: {_isRegular},
                        onSelectionChanged: (Set<bool> selection) {
                          setState(() {
                            _isRegular = selection.first;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
              ),
            ),
    );
  }
}
