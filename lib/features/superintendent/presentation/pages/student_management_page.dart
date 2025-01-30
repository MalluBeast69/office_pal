import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:developer' as developer;
import 'student_exam_registration_page.dart';

class StudentManagementPage extends ConsumerStatefulWidget {
  final String? initialDepartment;

  const StudentManagementPage({
    super.key,
    this.initialDepartment,
  });

  @override
  ConsumerState<StudentManagementPage> createState() =>
      _StudentManagementPageState();
}

class _StudentManagementPageState extends ConsumerState<StudentManagementPage> {
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> filteredStudents = [];
  bool isLoading = true;
  bool isInitializing = true;
  String searchQuery = '';
  String? selectedDepartment;
  int? selectedSemester;
  String? selectedRegStatus;
  List<String> departments = [];
  List<int> semesters = [];
  Map<String, List<Map<String, dynamic>>> studentCourses = {};

  @override
  void initState() {
    super.initState();
    selectedDepartment = widget.initialDepartment;
    loadStudents();
  }

  Future<void> loadStudents() async {
    try {
      developer.log('Loading students and courses...');

      // Load students first
      final studentsResponse = await Supabase.instance.client
          .from('student')
          .select('student_reg_no, student_name, dept_id, semester')
          .order('student_reg_no');

      developer.log('Loaded ${studentsResponse.length} students');

      // Load all registered courses with course details
      final coursesResponse =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            course_code,
            is_reguler,
            course:course_code (
              course_name,
              dept_id,
              credit
            )
          ''');

      developer.log('Loaded ${coursesResponse.length} course registrations');

      // Group courses by student
      final Map<String, List<Map<String, dynamic>>> coursesByStudent = {};
      for (final course in List<Map<String, dynamic>>.from(coursesResponse)) {
        final studentId = course['student_reg_no'] as String;
        coursesByStudent[studentId] = coursesByStudent[studentId] ?? [];
        coursesByStudent[studentId]!.add(course);
      }

      developer.log(
          'Grouped courses by student: ${coursesByStudent.keys.length} students have courses');

      // Debug course status for each student
      for (var entry in coursesByStudent.entries) {
        final regularCourses =
            entry.value.where((c) => c['is_reguler'] == true).length;
        final backlogCourses =
            entry.value.where((c) => c['is_reguler'] == false).length;
        developer.log(
            'Student ${entry.key}: Total=${entry.value.length}, Regular=$regularCourses, Backlog=$backlogCourses');
      }

      setState(() {
        students = List<Map<String, dynamic>>.from(studentsResponse);
        studentCourses = coursesByStudent;
        departments = students
            .map((s) => s['dept_id'].toString())
            .toSet()
            .toList()
          ..sort();
        semesters = students.map((s) => s['semester'] as int).toSet().toList()
          ..sort();

        // If initialDepartment is set but not in departments list, add it
        if (selectedDepartment != null &&
            !departments.contains(selectedDepartment)) {
          departments.add(selectedDepartment!);
          departments.sort();
        }

        filterStudents();
        isLoading = false;
        isInitializing = false;
      });
    } catch (error) {
      developer.log('Error loading data: $error', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: ${error.toString()}'),
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

  void filterStudents() {
    developer.log('Filtering students...');
    developer.log(
        'Current filters - Department: $selectedDepartment, Semester: $selectedSemester, RegStatus: $selectedRegStatus');

    setState(() {
      filteredStudents = students.where((student) {
        final studentId = student['student_reg_no'] as String;
        final courses = studentCourses[studentId] ?? [];

        developer.log('Filtering student $studentId:');
        developer.log('- Total courses: ${courses.length}');
        if (courses.isNotEmpty) {
          final regularCount =
              courses.where((c) => c['is_reguler'] == true).length;
          final backlogCount =
              courses.where((c) => c['is_reguler'] == false).length;
          developer.log('- Regular courses: $regularCount');
          developer.log('- Backlog courses: $backlogCount');
        }

        // Check search query
        final matchesSearch = searchQuery.isEmpty ||
            student['student_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            student['student_reg_no']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());

        // Check department
        final matchesDepartment = selectedDepartment == null ||
            student['dept_id'] == selectedDepartment;

        // Check semester
        final matchesSemester =
            selectedSemester == null || student['semester'] == selectedSemester;

        // Check registration status
        bool matchesRegStatus;
        if (selectedRegStatus == null) {
          matchesRegStatus = true;
        } else if (courses.isEmpty) {
          matchesRegStatus = false;
        } else if (selectedRegStatus == 'Regular') {
          // All courses must be regular
          matchesRegStatus =
              courses.every((course) => course['is_reguler'] == true);
        } else {
          // At least one backlog course
          matchesRegStatus =
              courses.any((course) => course['is_reguler'] == false);
        }

        developer.log('Filter results for $studentId:');
        developer.log('- Matches search: $matchesSearch');
        developer.log('- Matches department: $matchesDepartment');
        developer.log('- Matches semester: $matchesSemester');
        developer.log('- Matches reg status: $matchesRegStatus');

        return matchesSearch &&
            matchesDepartment &&
            matchesSemester &&
            matchesRegStatus;
      }).toList();

      developer.log('Filtered to ${filteredStudents.length} students');
    });
  }

  void _showImportOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Import Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Import Students'),
              subtitle: const Text('Add new students to the system'),
              onTap: () {
                Navigator.pop(context);
                importFromCsv(importType: 'students');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.assignment),
              title: const Text('Import Course Registrations'),
              subtitle: const Text('Register students for courses'),
              onTap: () {
                Navigator.pop(context);
                importFromCsv(importType: 'registrations');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> importFromCsv({required String importType}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      developer.log('File picker result: ${result?.files.length ?? 0} files');

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        developer.log('File name: ${file.name}');
        developer.log('File size: ${file.size} bytes');

        if (file.bytes == null) {
          throw Exception('No file content');
        }

        final csvString = String.fromCharCodes(file.bytes!);
        developer.log('CSV content: \n$csvString');

        final rows = csvString.split('\n');
        if (rows.isEmpty) {
          throw Exception('Empty file');
        }

        // Parse header to verify format
        final header = rows.first.trim().split(',');

        if (importType == 'students') {
          await _importStudents(header, rows);
        } else {
          await _importRegistrations(header, rows);
        }
      }
    } catch (error) {
      developer.log('Error importing CSV: $error', error: error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to import CSV: ${error.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _importStudents(List<String> header, List<String> rows) async {
    // Validate header format
    if (header.length != 4 ||
        header[0] != 'student_reg_no' ||
        header[1] != 'student_name' ||
        header[2] != 'dept_id' ||
        header[3] != 'semester') {
      throw Exception(
          'Invalid CSV format. Expected headers: student_reg_no,student_name,dept_id,semester');
    }

    // Get valid departments from database
    final departmentsResponse =
        await Supabase.instance.client.from('departments').select('dept_id');
    final validDepartments = List<String>.from(
        departmentsResponse.map((dept) => dept['dept_id'].toString()));

    // Get existing student IDs to check for duplicates
    final existingStudentsResponse =
        await Supabase.instance.client.from('student').select('student_reg_no');
    final existingStudentIds = List<String>.from(
        existingStudentsResponse.map((s) => s['student_reg_no'].toString()));

    final errors = <String>[];
    final students = <Map<String, dynamic>>[];
    int rowNumber = 1; // Skip header row

    // Parse and validate each row
    for (final row in rows.skip(1).where((row) => row.trim().isNotEmpty)) {
      rowNumber++;
      try {
        final columns = row.split(',');
        if (columns.length < 4) {
          errors.add('Row $rowNumber: Invalid number of columns');
          continue;
        }

        final studentId = columns[0].trim().toUpperCase();
        final deptId = columns[2].trim().toUpperCase();
        final semesterStr = columns[3].trim();

        // Validate student ID format
        if (!RegExp(r'^THAWS[A-Z]{2}\d{3}$').hasMatch(studentId)) {
          errors.add(
              'Row $rowNumber: Invalid student ID format (should be THAWS[DEPT][NUMBER])');
          continue;
        }

        // Check for duplicate in existing students
        if (existingStudentIds.contains(studentId)) {
          errors.add('Row $rowNumber: Student ID $studentId already exists');
          continue;
        }

        // Check for duplicate in current import
        if (students.any((s) => s['student_reg_no'] == studentId)) {
          errors.add(
              'Row $rowNumber: Duplicate student ID $studentId in import file');
          continue;
        }

        // Validate department
        if (!validDepartments.contains(deptId)) {
          errors.add('Row $rowNumber: Invalid department ID: $deptId');
          continue;
        }

        // Validate semester
        final semester = int.tryParse(semesterStr);
        if (semester == null || semester < 1 || semester > 8) {
          errors.add(
              'Row $rowNumber: Invalid semester (should be a number between 1 and 8)');
          continue;
        }

        students.add({
          'student_reg_no': studentId,
          'student_name': columns[1].trim(),
          'dept_id': deptId,
          'semester': semester,
        });
      } catch (e) {
        errors.add('Row $rowNumber: ${e.toString()}');
      }
    }

    // If there are any errors, show them and abort
    if (errors.isNotEmpty) {
      throw Exception(
          'Validation errors found:\n${errors.take(5).join('\n')}${errors.length > 5 ? '\n...and ${errors.length - 5} more errors' : ''}');
    }

    // Show preview dialog
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) => PreviewDialog(students: students),
    );

    if (shouldImport == true) {
      setState(() => isLoading = true);
      await Supabase.instance.client.from('student').insert(students);
      developer.log('Successfully imported students to database');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully imported ${students.length} students'),
          backgroundColor: Colors.green,
        ),
      );
      loadStudents();
    }
  }

  Future<void> _importRegistrations(
      List<String> header, List<String> rows) async {
    // Validate header format
    if (header.length != 3 ||
        header[0] != 'student_reg_no' ||
        header[1] != 'course_code' ||
        header[2] != 'is_reguler') {
      throw Exception(
          'Invalid CSV format. Expected headers: student_reg_no,course_code,is_reguler');
    }

    // Get valid student IDs
    final studentsResponse =
        await Supabase.instance.client.from('student').select('student_reg_no');
    final validStudentIds = List<String>.from(
        studentsResponse.map((s) => s['student_reg_no'].toString()));

    // Get valid course codes
    final coursesResponse =
        await Supabase.instance.client.from('course').select('course_code');
    final validCourseCodes = List<String>.from(
        coursesResponse.map((c) => c['course_code'].toString()));

    // Get existing registrations to check for duplicates
    final existingRegistrationsResponse = await Supabase.instance.client
        .from('registered_students')
        .select('student_reg_no, course_code');
    final existingRegistrations =
        List<Map<String, dynamic>>.from(existingRegistrationsResponse);

    final errors = <String>[];
    final registrations = <Map<String, dynamic>>[];
    int rowNumber = 1; // Skip header row

    // Parse and validate each row
    for (final row in rows.skip(1).where((row) => row.trim().isNotEmpty)) {
      rowNumber++;
      try {
        final columns = row.split(',');
        if (columns.length < 3) {
          errors.add('Row $rowNumber: Invalid number of columns');
          continue;
        }

        final studentId = columns[0].trim().toUpperCase();
        final courseCode = columns[1].trim().toUpperCase();
        final isRegularStr = columns[2].trim().toLowerCase();

        // Validate student ID
        if (!validStudentIds.contains(studentId)) {
          errors.add('Row $rowNumber: Student ID $studentId does not exist');
          continue;
        }

        // Validate course code
        if (!validCourseCodes.contains(courseCode)) {
          errors.add('Row $rowNumber: Course code $courseCode does not exist');
          continue;
        }

        // Check for existing registration
        if (existingRegistrations.any((r) =>
            r['student_reg_no'] == studentId &&
            r['course_code'] == courseCode)) {
          errors.add(
              'Row $rowNumber: Student $studentId is already registered for course $courseCode');
          continue;
        }

        // Check for duplicate in current import
        if (registrations.any((r) =>
            r['student_reg_no'] == studentId &&
            r['course_code'] == courseCode)) {
          errors.add(
              'Row $rowNumber: Duplicate registration for student $studentId and course $courseCode in import file');
          continue;
        }

        // Validate is_reguler value
        if (isRegularStr != 'true' && isRegularStr != 'false') {
          errors.add(
              'Row $rowNumber: Invalid is_reguler value (should be true or false)');
          continue;
        }

        registrations.add({
          'student_reg_no': studentId,
          'course_code': courseCode,
          'is_reguler': isRegularStr == 'true',
        });
      } catch (e) {
        errors.add('Row $rowNumber: ${e.toString()}');
      }
    }

    // If there are any errors, show them and abort
    if (errors.isNotEmpty) {
      throw Exception(
          'Validation errors found:\n${errors.take(5).join('\n')}${errors.length > 5 ? '\n...and ${errors.length - 5} more errors' : ''}');
    }

    // Show preview dialog
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) =>
          RegistrationPreviewDialog(registrations: registrations),
    );

    if (shouldImport == true) {
      setState(() => isLoading = true);
      await Supabase.instance.client
          .from('registered_students')
          .insert(registrations);
      developer.log('Successfully imported registrations to database');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Successfully imported ${registrations.length} course registrations'),
          backgroundColor: Colors.green,
        ),
      );
      loadStudents();
    }
  }

  Future<void> _addEditStudent({Map<String, dynamic>? student}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StudentDialog(student: student),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        if (student == null) {
          // Add new student
          await Supabase.instance.client.from('student').insert(result);
        } else {
          // Update existing student
          await Supabase.instance.client
              .from('student')
              .update(result)
              .eq('student_reg_no', student['student_reg_no']);
        }
        loadStudents();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                student == null
                    ? 'Failed to add student'
                    : 'Failed to update student',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteStudent(String regNo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this student?'),
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
            .from('student')
            .delete()
            .eq('student_reg_no', regNo);
        loadStudents();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete student'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _viewStudentCourses(String studentRegNo) async {
    setState(() => isLoading = true);
    try {
      developer.log('Loading courses for student: $studentRegNo');

      // First, verify if student exists
      final studentResponse = await Supabase.instance.client
          .from('student')
          .select()
          .eq('student_reg_no', studentRegNo)
          .single();

      developer.log('Student found: ${studentResponse != null}');

      // Get registered courses with course details
      final response =
          await Supabase.instance.client.from('registered_students').select('''
            course_code,
            is_reguler,
            course!inner (
              course_name,
              dept_id,
              credit
            )
          ''').eq('student_reg_no', studentRegNo);

      developer.log('Courses query response: $response');
      developer.log('Number of courses found: ${response?.length ?? 0}');

      if (mounted) {
        final courses = List<Map<String, dynamic>>.from(response);
        developer.log('Parsed courses: $courses');

        showDialog(
          context: context,
          builder: (context) => StudentCoursesDialog(
            courses: courses,
            studentRegNo: studentRegNo,
          ),
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Error loading student courses',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to load student courses: ${error.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isSmallScreen = MediaQuery.of(context).size.width < 500;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Management'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.app_registration),
            tooltip: 'Register for Exam',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StudentExamRegistrationPage(),
                ),
              ).then((_) => loadStudents());
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import Students',
            onPressed: _showImportOptions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => const AddStudentDialog(),
          );
          if (result == true) {
            loadStudents();
          }
        },
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name or registration number',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    searchQuery = value;
                    filterStudents();
                  },
                ),
                const SizedBox(height: 16),
                if (isSmallScreen) ...[
                  // Mobile layout for filters
                  DropdownButtonFormField<String>(
                    value: selectedDepartment,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        filterStudents();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedSemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Semesters'),
                      ),
                      ...semesters.map((sem) => DropdownMenuItem(
                            value: sem,
                            child: Text(sem.toString()),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedSemester = value;
                        filterStudents();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedRegStatus,
                    decoration: const InputDecoration(
                      labelText: 'Registration Status',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All Status'),
                      ),
                      DropdownMenuItem(
                        value: 'Regular',
                        child: Text('Regular Students'),
                      ),
                      DropdownMenuItem(
                        value: 'Backlog',
                        child: Text('Students with Backlogs'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedRegStatus = value;
                        filterStudents();
                      });
                    },
                  ),
                ] else ...[
                  // Desktop layout for filters
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
                              filterStudents();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
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
                                  child: Text(sem.toString()),
                                )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedSemester = value;
                              filterStudents();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRegStatus,
                    decoration: const InputDecoration(
                      labelText: 'Registration Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All Status'),
                      ),
                      DropdownMenuItem(
                        value: 'Regular',
                        child: Text('Regular Students'),
                      ),
                      DropdownMenuItem(
                        value: 'Backlog',
                        child: Text('Students with Backlogs'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedRegStatus = value;
                        filterStudents();
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredStudents.isEmpty
                    ? const Center(
                        child: Text(
                          'No students found',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredStudents.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          final courses =
                              studentCourses[student['student_reg_no']] ?? [];
                          final hasBacklogs =
                              courses.any((c) => c['is_reguler'] == false);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              student['student_name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (courses.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: hasBacklogs
                                                      ? Colors.orange
                                                          .withOpacity(0.1)
                                                      : Colors.green
                                                          .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: hasBacklogs
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      hasBacklogs
                                                          ? Icons.warning
                                                          : Icons.check_circle,
                                                      size: 14,
                                                      color: hasBacklogs
                                                          ? Colors.orange
                                                          : Colors.green,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      hasBacklogs
                                                          ? '${courses.where((c) => c['is_reguler'] == false).length} Backlogs'
                                                          : 'Regular',
                                                      style: TextStyle(
                                                        color: hasBacklogs
                                                            ? Colors.orange
                                                            : Colors.green,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.menu_book),
                                            tooltip: 'View Courses',
                                            onPressed: () =>
                                                _viewStudentCourses(
                                                    student['student_reg_no']),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            iconSize: 18,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            tooltip: 'Edit Student',
                                            onPressed: () => _addEditStudent(
                                                student: student),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            iconSize: 18,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red),
                                            tooltip: 'Delete Student',
                                            onPressed: () => _deleteStudent(
                                                student['student_reg_no']),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            iconSize: 18,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reg No: ${student['student_reg_no']}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Department: ${student['dept_id']}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Semester: ${student['semester']}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total Courses: ${courses.length}${hasBacklogs ? ' (${courses.where((c) => c['is_reguler'] == true).length} Regular)' : ''}',
                                    style: const TextStyle(fontSize: 13),
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

class StudentDialog extends StatefulWidget {
  final Map<String, dynamic>? student;

  const StudentDialog({super.key, this.student});

  @override
  State<StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<StudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _regNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _deptController = TextEditingController();
  final _semesterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.student != null) {
      _regNoController.text = widget.student!['student_reg_no'];
      _nameController.text = widget.student!['student_name'];
      _deptController.text = widget.student!['dept_id'];
      _semesterController.text = widget.student!['semester'].toString();
    }
  }

  @override
  void dispose() {
    _regNoController.dispose();
    _nameController.dispose();
    _deptController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.student != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Student' : 'Add Student'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _regNoController,
                decoration:
                    const InputDecoration(labelText: 'Registration Number'),
                enabled:
                    !isEditing, // Disable editing of reg no for existing students
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter registration number';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Student Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter student name';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _deptController,
                decoration: const InputDecoration(labelText: 'Department ID'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department ID';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _semesterController,
                decoration: const InputDecoration(labelText: 'Semester'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter semester';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
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
                'student_reg_no': _regNoController.text.trim().toUpperCase(),
                'student_name': _nameController.text.trim(),
                'dept_id': _deptController.text.trim().toUpperCase(),
                'semester': int.parse(_semesterController.text.trim()),
              });
            }
          },
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}

class PreviewDialog extends StatelessWidget {
  final List<Map<String, dynamic>> students;

  const PreviewDialog({
    super.key,
    required this.students,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preview Import Data'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Found ${students.length} students to import:'),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return ListTile(
                      dense: true,
                      title: Text(student['student_name']),
                      subtitle: Text(
                        '${student['student_reg_no']} - ${student['dept_id']} (Semester ${student['semester']})',
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class StudentCoursesDialog extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  final String studentRegNo;

  const StudentCoursesDialog({
    super.key,
    required this.courses,
    required this.studentRegNo,
  });

  @override
  State<StudentCoursesDialog> createState() => _StudentCoursesDialogState();
}

class _StudentCoursesDialogState extends State<StudentCoursesDialog> {
  String? selectedStatus;
  List<Map<String, dynamic>> filteredCourses = [];

  @override
  void initState() {
    super.initState();
    filteredCourses = widget.courses;
  }

  void _filterCourses(String? status) {
    setState(() {
      selectedStatus = status;
      if (status == null) {
        filteredCourses = widget.courses;
      } else {
        final isRegular = status == 'Regular';
        filteredCourses = widget.courses
            .where((course) => course['is_reguler'] == isRegular)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Courses - ${widget.studentRegNo}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total Courses: ${filteredCourses.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: selectedStatus,
                  hint: const Text('All Status'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('All Status'),
                    ),
                    DropdownMenuItem(
                      value: 'Regular',
                      child: Text('Regular'),
                    ),
                    DropdownMenuItem(
                      value: 'Backlog',
                      child: Text('Backlog'),
                    ),
                  ],
                  onChanged: _filterCourses,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: filteredCourses.isEmpty
                    ? Center(
                        child: Text(
                          selectedStatus == null
                              ? 'No courses registered'
                              : 'No $selectedStatus courses found',
                          style: const TextStyle(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredCourses.length,
                        itemBuilder: (context, index) {
                          final course = filteredCourses[index];
                          final courseDetails =
                              course['course'] as Map<String, dynamic>;
                          final isRegular = course['is_reguler'] as bool;
                          return Card(
                            child: ListTile(
                              leading: Container(
                                width: 4,
                                height: double.infinity,
                                color: isRegular ? Colors.green : Colors.orange,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(courseDetails['course_name']),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isRegular
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isRegular
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                    child: Text(
                                      isRegular ? 'Regular' : 'Backlog',
                                      style: TextStyle(
                                        color: isRegular
                                            ? Colors.green
                                            : Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Code: ${course['course_code']}\n'
                                'Department: ${courseDetails['dept_id']}\n'
                                'Credits: ${courseDetails['credit']}',
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class RegistrationPreviewDialog extends StatelessWidget {
  final List<Map<String, dynamic>> registrations;

  const RegistrationPreviewDialog({
    super.key,
    required this.registrations,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preview Course Registrations'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Found ${registrations.length} registrations to import:'),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: registrations.length,
                  itemBuilder: (context, index) {
                    final reg = registrations[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        reg['is_reguler'] ? Icons.check_circle : Icons.warning,
                        color: reg['is_reguler'] ? Colors.green : Colors.orange,
                      ),
                      title: Text(
                          '${reg['student_reg_no']} - ${reg['course_code']}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: reg['is_reguler']
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: reg['is_reguler']
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        child: Text(
                          reg['is_reguler'] ? 'Regular' : 'Backlog',
                          style: TextStyle(
                            color: reg['is_reguler']
                                ? Colors.green
                                : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({super.key});

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _semesterController = TextEditingController();
  bool _isLoading = false;
  String? _selectedDepartment;
  String? _generatedRegNo;
  List<String> _departments = [];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await Supabase.instance.client
          .from('departments')
          .select('dept_id')
          .order('dept_id');

      if (mounted) {
        setState(() {
          _departments = List<String>.from(
              response.map((dept) => dept['dept_id'].toString()));
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading departments: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _generateRegNo(String deptId) async {
    try {
      // Get the latest registration number for the department
      final response = await Supabase.instance.client
          .from('student')
          .select('student_reg_no')
          .ilike('student_reg_no', 'THAWS${deptId.substring(2)}%')
          .order('student_reg_no', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        // Extract the number part and increment
        final lastRegNo = response['student_reg_no'] as String;
        final lastNumber = int.parse(lastRegNo.substring(7));
        final newNumber = lastNumber + 1;
        return 'THAWS${deptId.substring(2)}${newNumber.toString().padLeft(3, '0')}';
      } else {
        // If no existing students in department, start with 001
        return 'THAWS${deptId.substring(2)}001';
      }
    } catch (error) {
      throw Exception('Error generating registration number: $error');
    }
  }

  Future<void> _addStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDepartment == null) return;

    setState(() => _isLoading = true);
    try {
      // Check if registration number is still available
      final existingStudent = await Supabase.instance.client
          .from('student')
          .select()
          .eq('student_reg_no', _generatedRegNo as Object)
          .maybeSingle();

      if (existingStudent != null) {
        throw Exception(
            'Registration number is no longer available. Please try again.');
      }

      // Add new student
      await Supabase.instance.client.from('student').insert({
        'student_reg_no': _generatedRegNo,
        'student_name': _nameController.text.trim(),
        'dept_id': _selectedDepartment,
        'semester': int.parse(_semesterController.text.trim()),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding student: $error'),
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
    return AlertDialog(
      title: const Text('Add New Student'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Department Selection
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  hintText: 'Select department',
                ),
                items: _departments.map((dept) {
                  return DropdownMenuItem(
                    value: dept,
                    child: Text(dept),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
                onChanged: (value) async {
                  if (value != null) {
                    setState(() {
                      _selectedDepartment = value;
                      _generatedRegNo = null;
                      _isLoading = true;
                    });
                    try {
                      final regNo = await _generateRegNo(value);
                      if (mounted) {
                        setState(() {
                          _generatedRegNo = regNo;
                          _isLoading = false;
                        });
                      }
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $error'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        setState(() => _isLoading = false);
                      }
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              // Registration Number Display
              TextFormField(
                initialValue: _generatedRegNo,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Registration Number',
                  hintText: 'Auto-generated after department selection',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Student Name',
                  hintText: 'Enter full name',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter student name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _semesterController,
                decoration: const InputDecoration(
                  labelText: 'Semester',
                  hintText: 'Enter semester (1-8)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter semester';
                  }
                  final semester = int.tryParse(value);
                  if (semester == null || semester < 1 || semester > 8) {
                    return 'Semester must be between 1 and 8';
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
        FilledButton(
          onPressed: _isLoading || _generatedRegNo == null ? null : _addStudent,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('Add Student'),
        ),
      ],
    );
  }
}
