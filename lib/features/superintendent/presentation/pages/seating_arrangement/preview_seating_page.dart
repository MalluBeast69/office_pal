import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;
import '../../pages/student_management_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

class PreviewSeatingPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;
  final List<String> selectedStudents;
  final List<Map<String, dynamic>> selectedHalls;
  final Map<String, String>
      hallFacultyMap; // Format: 'hallId|session|date' -> facultyId

  const PreviewSeatingPage({
    super.key,
    required this.exams,
    required this.selectedStudents,
    required this.selectedHalls,
    required this.hallFacultyMap,
  });

  @override
  ConsumerState<PreviewSeatingPage> createState() => _PreviewSeatingPageState();
}

class _PreviewSeatingPageState extends ConsumerState<PreviewSeatingPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _halls = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _faculty = [];
  final Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>
      _seatingArrangements = {};

  DateTime? _selectedDate;
  String? _selectedSession;
  String? _selectedExam;
  final Set<String> _expandedHalls = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // Load halls data
      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .in_('hall_id',
              widget.selectedHalls.map((h) => h['hall_id']).toList());
      _halls = List<Map<String, dynamic>>.from(hallsResponse);

      // Load course names for exams
      final courseIds =
          widget.exams.map((e) => e['course_id']).toSet().toList();
      final coursesResponse = await Supabase.instance.client
          .from('course')
          .select('course_code, course_name')
          .in_('course_code', courseIds);

      // Update exam data with course names
      final courseMap = {
        for (var course in coursesResponse)
          course['course_code']: course['course_name']
      };

      for (var exam in widget.exams) {
        exam['course_name'] = courseMap[exam['course_id']] ?? 'Unknown Course';
      }

      // Load students data with course information
      final studentsResponse = await Supabase.instance.client
          .from('registered_students')
          .select('''
            student_reg_no,
            course_code,
            is_reguler,
            student!inner (
              student_name,
              dept_id,
              semester
            )
          ''')
          .in_('student_reg_no', widget.selectedStudents.toList())
          .in_('course_code', courseIds);

      // Transform the data to match our needs
      _students = List<Map<String, dynamic>>.from(studentsResponse).map((s) {
        return {
          'student_reg_no': s['student_reg_no'],
          'course_code': s['course_code'],
          'is_supplementary': !s['is_reguler'],
          'student': s['student'],
          'row_no': 0,
          'column_no': 0,
        };
      }).toList();

      // Load faculty data
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .in_('faculty_id', widget.hallFacultyMap.values.toList());
      _faculty = List<Map<String, dynamic>>.from(facultyResponse);

      // Generate seating arrangements
      await _generateSeatingArrangement();

      // Set initial date and session
      if (_seatingArrangements.isNotEmpty) {
        final firstDate = _seatingArrangements.keys.first;
        _selectedDate = DateTime.parse(firstDate);
        if (_seatingArrangements[firstDate]?.isNotEmpty ?? false) {
          _selectedSession = _seatingArrangements[firstDate]!.keys.first;
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error, stackTrace) {
      developer.log('Error loading data:',
          error: error, stackTrace: stackTrace);
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

  Future<void> _generateSeatingArrangement() async {
    try {
      setState(() => _isLoading = true);

      developer.log('\n=== Starting Seating Arrangement Generation ===');
      developer.log(
          'Total Students to be Seated: ${widget.selectedStudents.length}');

      _seatingArrangements.clear();

      // Group halls by date and session
      final hallsByDateAndSession =
          <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final hall in widget.selectedHalls) {
        final date = hall['exam_date'].toString().split(' ')[0];
        final session = hall['session'] as String;
        hallsByDateAndSession[date] ??= {};
        hallsByDateAndSession[date]![session] ??= [];
        hallsByDateAndSession[date]![session]!.add(hall);
      }

      developer.log('\nHall Distribution:');
      hallsByDateAndSession.forEach((date, sessions) {
        developer.log('Date: $date');
        sessions.forEach((session, halls) {
          developer.log('  Session: $session');
          developer
              .log('  Halls: ${halls.map((h) => h['hall_id']).join(', ')}');
        });
      });

      // Track all unassigned students across all sessions
      final allUnassignedStudents = <Map<String, dynamic>>[];
      final allAssignedStudents = <String>{};
      final totalSeatedByHall = <String, int>{};

      // Process each date
      for (final date in hallsByDateAndSession.keys) {
        _seatingArrangements[date] ??= {};
        developer.log('\nProcessing Date: $date');

        // Process each session
        for (final session in hallsByDateAndSession[date]!.keys) {
          _seatingArrangements[date]![session] ??= {};
          developer.log('\n  Processing Session: $session');

          // Get exams for this session
          final examsForSession = widget.exams
              .where((e) =>
                  e['session'] == session &&
                  e['exam_date'].toString().split(' ')[0] == date)
              .toList();

          developer.log(
              '  Exams in this session: ${examsForSession.map((e) => e['course_id']).join(', ')}');

          // Get all students for this session's exams
          final studentsForSession = <Map<String, dynamic>>[];
          for (final exam in examsForSession) {
            final courseId = exam['course_id'] as String;
            final examStudents =
                _students.where((s) => s['course_code'] == courseId).toList();
            studentsForSession.addAll(examStudents);
            developer
                .log('    Course $courseId: ${examStudents.length} students');
          }

          developer
              .log('  Total students in session: ${studentsForSession.length}');

          // Sort halls by capacity (largest first)
          final availableHalls = hallsByDateAndSession[date]![session]!
            ..sort((a, b) => calculateEffectiveHallCapacity(b)
                .compareTo(calculateEffectiveHallCapacity(a)));

          var remainingStudents =
              List<Map<String, dynamic>>.from(studentsForSession);
          var selectedHalls = <Map<String, dynamic>>[];
          var totalCapacityNeeded = studentsForSession.length;
          var currentCapacity = 0;

          developer.log('\n  Hall Selection:');
          developer.log('  Total capacity needed: $totalCapacityNeeded');

          // Select only needed halls
          for (final hall in availableHalls) {
            if (remainingStudents.isEmpty ||
                currentCapacity >= totalCapacityNeeded) {
              developer.log(
                  '  Sufficient capacity reached. Stopping hall selection.');
              break;
            }

            final effectiveCapacity = calculateEffectiveHallCapacity(hall);
            developer.log(
                '  Evaluating Hall ${hall['hall_id']}: Effective capacity = $effectiveCapacity');

            if (effectiveCapacity > 0) {
              selectedHalls.add(hall);
              currentCapacity += effectiveCapacity;
              developer.log(
                  '  Selected Hall ${hall['hall_id']}. Current total capacity: $currentCapacity');
            }
          }

          developer.log('\n  Selected Halls for Processing:');
          developer.log(
              '  Halls: ${selectedHalls.map((h) => h['hall_id']).join(', ')}');

          // Process only selected halls
          for (final hall in selectedHalls) {
            final hallId = hall['hall_id'].toString();
            _seatingArrangements[date]![session]![hallId] = [];
            developer.log('\n    Processing Hall: $hallId');

            final rows = hall['no_of_rows'] as int;
            final cols = hall['no_of_columns'] as int;
            final grid = List.generate(
              rows,
              (_) => List<String?>.filled(cols, null, growable: false),
            );

            var seatedInThisHall = 0;
            var uniqueStudentsInHall = <String>{};

            // Process each exam's students
            for (final exam in examsForSession) {
              final courseId = exam['course_id'] as String;
              final examId = exam['exam_id'] as String;

              final examStudents = studentsForSession
                  .where((s) =>
                      s['course_code'] == courseId &&
                      !allAssignedStudents.contains(s['student_reg_no']))
                  .toList();

              developer.log(
                  '      Course $courseId: Attempting to seat ${examStudents.length} students');

              for (var i = 0; i < rows; i++) {
                for (var j = 0; j < cols; j++) {
                  if (examStudents.isEmpty) break;
                  if (grid[i][j] == null &&
                      _isSeatSuitable(grid, i, j, courseId)) {
                    final student = examStudents.removeAt(0);
                    grid[i][j] = courseId;

                    final studentWithSeat = Map<String, dynamic>.from(student);
                    studentWithSeat['row_no'] = i;
                    studentWithSeat['column_no'] = j;
                    studentWithSeat['exam_id'] = examId;

                    _seatingArrangements[date]![session]![hallId]!
                        .add(studentWithSeat);
                    allAssignedStudents.add(student['student_reg_no']);
                    uniqueStudentsInHall.add(student['student_reg_no']);
                    seatedInThisHall++;
                  }
                }
                if (examStudents.isEmpty) break;
              }
            }

            totalSeatedByHall[hallId] = seatedInThisHall;
            developer
                .log('      Seated in this hall: $seatedInThisHall students');
            developer.log(
                '      Unique students in hall: ${uniqueStudentsInHall.length}');
          }
        }
      }

      developer.log('\n=== Final Seating Summary ===');
      developer
          .log('Total Students to Seat: ${widget.selectedStudents.length}');
      developer.log(
          'Total Seats Assigned: ${totalSeatedByHall.values.fold(0, (sum, count) => sum + count)}');
      developer.log('Unique Students Seated: ${allAssignedStudents.length}');

      developer.log('\nBreakdown by Hall:');
      totalSeatedByHall.forEach((hallId, count) {
        developer.log('  Hall $hallId: $count students');
      });

      // Clean up empty halls
      for (final date in _seatingArrangements.keys.toList()) {
        for (final session in _seatingArrangements[date]!.keys.toList()) {
          for (final hallId
              in _seatingArrangements[date]![session]!.keys.toList()) {
            if (_seatingArrangements[date]![session]![hallId]!.isEmpty) {
              developer.log('  Removing empty hall: $hallId');
              _seatingArrangements[date]![session]!.remove(hallId);
            }
          }
        }
      }

      if (allUnassignedStudents.isNotEmpty) {
        developer.log(
            '\nWARNING: ${allUnassignedStudents.length} students could not be seated:');
        final unassignedByCourse = <String, List<String>>{};
        for (final student in allUnassignedStudents) {
          final courseId = student['course_code'] as String;
          unassignedByCourse[courseId] ??= [];
          unassignedByCourse[courseId]!
              .add(student['student_reg_no'] as String);
        }

        unassignedByCourse.forEach((courseId, students) {
          developer.log('  Course: $courseId');
          developer.log('  Unassigned Students: ${students.join(", ")}');
        });
      }
    } catch (error) {
      developer.log('Error in seating generation: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error generating seating arrangement: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Calculate effective capacity of a hall considering seating rules
  int calculateEffectiveHallCapacity(Map<String, dynamic> hall) {
    final rows = hall['no_of_rows'] as int;
    final cols = hall['no_of_columns'] as int;

    // Create a grid and try to fill it with a dummy course
    final grid = List.generate(
      rows,
      (_) => List<String?>.filled(cols, null, growable: false),
      growable: false,
    );

    int effectiveCapacity = 0;
    final dummyCourses = [
      'TEST1',
      'TEST2',
      'TEST3',
      'TEST4'
    ]; // Multiple dummy courses
    var currentCourseIndex = 0;

    // Try to fill positions in a more efficient pattern using multiple dummy courses
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (grid[row][col] == null) {
          // Try each dummy course until we find one that fits
          for (var i = 0; i < dummyCourses.length; i++) {
            final courseIndex = (currentCourseIndex + i) % dummyCourses.length;
            if (_isSeatSuitable(grid, row, col, dummyCourses[courseIndex])) {
              grid[row][col] = dummyCourses[courseIndex];
              effectiveCapacity++;
              currentCourseIndex = (courseIndex + 1) % dummyCourses.length;
              break;
            }
          }
        }
      }
    }

    // Return a slightly reduced capacity to account for real-world distribution
    return (effectiveCapacity * 0.95).floor();
  }

  bool _isSeatSuitable(
      List<List<String?>> grid, int row, int col, String courseId) {
    final rows = grid.length;
    final cols = grid[0].length;

    // Check immediate adjacent and diagonal positions
    final positions = [
      [-1, -1], // Top-left
      [-1, 0], // Top
      [-1, 1], // Top-right
      [0, -1], // Left
      [0, 1], // Right
      [1, -1], // Bottom-left
      [1, 0], // Bottom
      [1, 1], // Bottom-right
    ];

    // Check each position
    for (final pos in positions) {
      final newRow = row + pos[0];
      final newCol = col + pos[1];

      if (newRow >= 0 && newRow < rows && newCol >= 0 && newCol < cols) {
        final adjacentCourse = grid[newRow][newCol];
        if (adjacentCourse == courseId) {
          return false; // Don't allow same course in adjacent or diagonal positions
        }
      }
    }

    return true;
  }

  Widget _buildSeatingGrid(
      Map<String, dynamic> hall, List<Map<String, dynamic>> students) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final seatWidth = math.min(
            80.0,
            (availableWidth - (hall['no_of_columns'] - 1) * 16) /
                hall['no_of_columns']);

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Teacher's desk at the top
              InkWell(
                onTap: () => _showTeacherInfo(hall['hall_id']),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: const BoxConstraints(
                    minWidth: 160,
                    minHeight: 48,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.brown.shade300,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Teacher\'s Desk',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tap to view details',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Student seating grid
              for (int row = 0; row < hall['no_of_rows']; row++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int col = 0; col < hall['no_of_columns']; col++) ...[
                      SizedBox(
                        width: seatWidth,
                        child: _buildSeat(row, col, students, hall),
                      ),
                      if (col < hall['no_of_columns'] - 1)
                        const SizedBox(width: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeat(int row, int col, List<Map<String, dynamic>> students,
      Map<String, dynamic> hall) {
    final student = students.firstWhere(
      (s) => s['row_no'] == row && s['column_no'] == col,
      orElse: () => <String, dynamic>{},
    );
    final isOccupied = student.isNotEmpty;
    final seatNumber = row * hall['no_of_columns'] + col + 1;
    final isHighlighted = _selectedExam == null ||
        (isOccupied && student['course_code'] == _selectedExam);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isOccupied ? () => _viewStudentDetails(student) : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: isHighlighted ? 1.0 : 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Desk
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.brown.shade400,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Always show seat number
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Text(
                        '$seatNumber',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isOccupied)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            student['student_reg_no']
                                .toString()
                                .substring(0, 4),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Student icon
              Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isOccupied
                      ? (student['is_supplementary'] as bool
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary)
                      : Colors.grey.shade300,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Icon(
                  isOccupied ? Icons.school : Icons.chair,
                  color: isOccupied ? Colors.white : Colors.grey.shade400,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewStudentDetails(Map<String, dynamic> student) async {
    try {
      developer.log('Viewing student details:');
      developer.log('Raw student data: $student');

      final studentRegNo = student['student_reg_no'];
      final studentData = student['student'];
      final courseCode = student['course_code'];
      final isSupplementary = student['is_supplementary'];
      final rowNo = student['row_no'];
      final colNo = student['column_no'];

      // Find exam details
      final exam = widget.exams.firstWhere(
        (e) => e['course_id'] == courseCode,
        orElse: () => <String, dynamic>{},
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Exam Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_document,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Exam Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$courseCode - ${exam['course_name'] ?? 'N/A'}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildExamDetailChip(
                          Icons.calendar_today,
                          DateFormat('MMM d, y').format(
                            DateTime.parse(exam['exam_date'].toString()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildExamDetailChip(
                          Icons.access_time,
                          exam['time']?.toString() ?? 'N/A',
                        ),
                        const SizedBox(width: 8),
                        _buildExamDetailChip(
                          Icons.person,
                          isSupplementary ? 'Supplementary' : 'Regular',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Student Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSupplementary
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.school,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentData['student_name'] ?? 'N/A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            studentRegNo,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Additional Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow(
                      'Department',
                      studentData['dept_id'] ?? 'N/A',
                      icon: Icons.business,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Semester',
                      '${studentData['semester'] ?? 'N/A'}',
                      icon: Icons.school,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Seat',
                      'Row ${rowNo + 1}, Column ${colNo + 1}',
                      icon: Icons.chair,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.person_search),
              label: const Text('View Full Profile'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StudentManagementPage(
                      initialDepartment: studentData['dept_id']?.toString(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      developer.log('Error viewing student details:',
          error: error, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error viewing student details: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildExamDetailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
        ],
        Text(
          '$label:',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTeacherInfo(String hallId) async {
    if (_selectedDate == null || _selectedSession == null) return;
    final currentDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final facultyId =
        widget.hallFacultyMap['$hallId|$_selectedSession|$currentDate'];
    if (facultyId == null) return;

    final faculty = _faculty.firstWhere(
      (f) {
        final hallSessionKey = '$hallId|$_selectedSession|$currentDate';
        return f['faculty_id'] == widget.hallFacultyMap[hallSessionKey];
      },
      orElse: () =>
          {'faculty_id': 'N/A', 'faculty_name': 'No faculty assigned'},
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.brown.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 16),
            const Text('Assigned Teacher'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Name', faculty['faculty_name']),
            _buildDetailRow('Faculty ID', faculty['faculty_id']),
            _buildDetailRow('Department', faculty['dept_id']),
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

  @override
  Widget build(BuildContext context) {
    if (_seatingArrangements.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Preview Seating'),
        ),
        body: const Center(
          child: Text('No seating arrangements available'),
        ),
      );
    }

    final currentDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final currentSessions = _seatingArrangements[currentDate] ?? {};
    final currentSession = _selectedSession ??
        (currentSessions.isNotEmpty ? currentSessions.keys.first : null);
    final currentSeating =
        currentSession != null ? currentSessions[currentSession] ?? {} : {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Seating'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.print),
                    SizedBox(width: 8),
                    Text('Print All Arrangements'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'selected',
                child: Row(
                  children: [
                    Icon(Icons.filter_list),
                    SizedBox(width: 8),
                    Text('Print Current View'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'all':
                  _generateAndOpenPDF(printAll: true);
                  break;
                case 'selected':
                  _generateAndOpenPDF(printAll: false);
                  break;
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Date and Session Selection
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
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
                                  'Date',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 40,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _seatingArrangements.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final dateStr = _seatingArrangements.keys
                                          .elementAt(index);
                                      final isSelected = dateStr == currentDate;
                                      return FilterChip(
                                        selected: isSelected,
                                        showCheckmark: false,
                                        onSelected: (bool selected) {
                                          if (selected) {
                                            setState(() {
                                              _selectedDate =
                                                  DateTime.parse(dateStr);
                                              if (_seatingArrangements[dateStr]
                                                      ?.isNotEmpty ??
                                                  false) {
                                                _selectedSession =
                                                    _seatingArrangements[
                                                            dateStr]!
                                                        .keys
                                                        .first;
                                              }
                                              _selectedExam = null;
                                            });
                                          }
                                        },
                                        label: Text(DateFormat('MMM d, y')
                                            .format(DateTime.parse(dateStr))),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Session',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 40,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: currentSessions.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final session =
                                          currentSessions.keys.elementAt(index);
                                      final isSelected =
                                          session == currentSession;
                                      return FilterChip(
                                        selected: isSelected,
                                        showCheckmark: false,
                                        label: Text(
                                            _getSessionDisplayName(session)),
                                        onSelected: (_) {
                                          setState(() {
                                            _selectedSession = session;
                                            _selectedExam = null;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (currentSeating.isNotEmpty)
                        _buildExamFilter(
                            Map<String, List<Map<String, dynamic>>>.from(
                                currentSeating)),
                    ],
                  ),
                ),
                // Hall Seating Arrangements
                Expanded(
                  child: currentSeating.isEmpty
                      ? const Center(
                          child:
                              Text('No seating arrangements for this session'),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              mainAxisExtent: 180,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: currentSeating.length,
                            itemBuilder: (context, index) {
                              final hallId =
                                  currentSeating.keys.elementAt(index);
                              final students = currentSeating[hallId]!;
                              final hall = _halls
                                  .firstWhere((h) => h['hall_id'] == hallId);
                              final faculty = _faculty.firstWhere(
                                (f) {
                                  final hallSessionKey =
                                      '$hallId|$_selectedSession|$currentDate';
                                  return f['faculty_id'] ==
                                      widget.hallFacultyMap[hallSessionKey];
                                },
                                orElse: () => {
                                  'faculty_id': 'N/A',
                                  'faculty_name': 'No faculty assigned'
                                },
                              );

                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    _showSeatingArrangementDialog(
                                      context,
                                      hall,
                                      students,
                                      faculty,
                                    );
                                  },
                                  child: SizedBox(
                                    height: 180,
                                    child: Stack(
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Hall Header
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          'Hall $hallId',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleLarge,
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          faculty[
                                                              'faculty_name'],
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (students
                                                      .isEmpty) // Only show delete option for empty halls
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.delete_outline),
                                                      tooltip:
                                                          'Remove empty hall',
                                                      onPressed: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (context) =>
                                                              AlertDialog(
                                                            title: const Text(
                                                                'Remove Empty Hall'),
                                                            content: Text(
                                                                'Are you sure you want to remove Hall $hallId from the arrangement?'),
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
                                                                  setState(() {
                                                                    if (_selectedDate !=
                                                                            null &&
                                                                        _selectedSession !=
                                                                            null) {
                                                                      final date = DateFormat(
                                                                              'yyyy-MM-dd')
                                                                          .format(
                                                                              _selectedDate!);
                                                                      _seatingArrangements[date]![
                                                                              _selectedSession]!
                                                                          .remove(
                                                                              hallId);
                                                                    }
                                                                  });
                                                                  Navigator.pop(
                                                                      context);
                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                    SnackBar(
                                                                      content: Text(
                                                                          'Hall $hallId removed from arrangement'),
                                                                      duration: const Duration(
                                                                          seconds:
                                                                              2),
                                                                    ),
                                                                  );
                                                                },
                                                                child: const Text(
                                                                    'Remove'),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                ],
                                              ),
                                            ),
                                            // Statistics
                                            Expanded(
                                              child: Center(
                                                child: LayoutBuilder(
                                                  builder:
                                                      (context, constraints) {
                                                    return Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        // Student Count
                                                        FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            '${students.length}',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .headlineLarge
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          'Students',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleMedium,
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        // Stats Row
                                                        Flexible(
                                                          child:
                                                              SingleChildScrollView(
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            child: Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                _buildStatChip(
                                                                  context,
                                                                  'Regular',
                                                                  students
                                                                      .where((s) =>
                                                                          !(s['is_supplementary']
                                                                              as bool))
                                                                      .length
                                                                      .toString(),
                                                                  Icons.person,
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                _buildStatChip(
                                                                  context,
                                                                  'Supplementary',
                                                                  students
                                                                      .where((s) =>
                                                                          s['is_supplementary']
                                                                              as bool)
                                                                      .length
                                                                      .toString(),
                                                                  Icons
                                                                      .person_outline,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Info Icon with Hover
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: MouseRegion(
                                            child: Tooltip(
                                              preferBelow: false,
                                              richMessage: TextSpan(
                                                children: [
                                                  const TextSpan(
                                                    text:
                                                        'Exams in this hall:\n',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                  ...students
                                                      .map((s) =>
                                                          s['course_code'])
                                                      .toSet()
                                                      .map((courseCode) {
                                                    final exam =
                                                        widget.exams.firstWhere(
                                                      (e) =>
                                                          e['course_id'] ==
                                                          courseCode,
                                                      orElse: () =>
                                                          <String, dynamic>{},
                                                    );
                                                    return TextSpan(
                                                      text:
                                                          '\n• $courseCode - ${exam['course_name'] ?? 'N/A'}',
                                                    );
                                                  }),
                                                  const TextSpan(
                                                      text:
                                                          '\n\nFaculty Details:'),
                                                  TextSpan(
                                                      text:
                                                          '\nID: ${faculty['faculty_id']}'),
                                                  TextSpan(
                                                      text:
                                                          '\nDepartment: ${faculty['dept_id']}'),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.info_outline,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FilledButton.icon(
          icon: const Icon(Icons.save),
          label: Text(_isSaving ? 'Saving...' : 'Save Arrangement'),
          onPressed: _isSaving ? null : _saveSeatingArrangement,
        ),
      ),
    );
  }

  Future<void> _saveSeatingArrangement() async {
    try {
      setState(() => _isSaving = true);

      developer.log('=== Starting Seating Save ===');
      developer.log('Arrangements to save: ${_seatingArrangements.length}');

      // Generate a unique arrangement ID for this batch
      final arrangementId = const Uuid().v4();
      developer.log('Generated arrangement ID: $arrangementId');

      // Build arrangements list from nested structure
      final arrangementsToInsert = <Map<String, dynamic>>[];

      for (final dateEntry in _seatingArrangements.entries) {
        final date = dateEntry.key;
        for (final sessionEntry in dateEntry.value.entries) {
          final session = sessionEntry.key;
          for (final hallEntry in sessionEntry.value.entries) {
            final hallId = hallEntry.key;
            for (final student in hallEntry.value) {
              arrangementsToInsert.add({
                'arrangement_id': arrangementId,
                'exam_id': student['exam_id'],
                'hall_id': hallId,
                'faculty_id': widget.hallFacultyMap['$hallId|$session|$date'],
                'student_reg_no': student['student_reg_no'],
                'column_no': student['column_no'],
                'row_no': student['row_no'],
              });
            }
          }
        }
      }

      // Insert in batches
      const batchSize = 100;
      for (var i = 0; i < arrangementsToInsert.length; i += batchSize) {
        final end = (i + batchSize < arrangementsToInsert.length)
            ? i + batchSize
            : arrangementsToInsert.length;
        final batch = arrangementsToInsert.sublist(i, end);

        await Supabase.instance.client.from('seating_arr').insert(batch);
        developer.log(
            'Saved batch ${(i ~/ batchSize) + 1}: ${batch.length} arrangements');
      }

      developer.log('=== Seating Save Complete ===');
      developer.log('Total arrangements saved: ${arrangementsToInsert.length}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Seating arrangements saved successfully')),
        );
      }
    } catch (error) {
      developer.log('ERROR in seating save: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving seating arrangements: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _generateAndOpenPDF({required bool printAll}) async {
    try {
      setState(() => _isLoading = true);

      developer.log('\n=== Starting PDF Generation ===');

      // Create PDF document
      final pdf = pw.Document();

      // Define consistent cell size and styling
      final headerStyle = pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      );
      const normalStyle = pw.TextStyle(fontSize: 9);
      const smallStyle = pw.TextStyle(fontSize: 7);

      // Determine which arrangements to process
      final arrangementsToProcess = printAll
          ? _seatingArrangements
          : {
              _selectedDate!.toString().split(' ')[0]: {
                _selectedSession!: _seatingArrangements[
                    _selectedDate!.toString().split(' ')[0]]![_selectedSession]!
              }
            };

      developer.log('Arrangements to process:');
      developer.log('Total dates: ${arrangementsToProcess.length}');

      // Group arrangements by date and session
      final arrangementsByDateAndSession =
          <String, Map<String, Map<String, List<Map<String, dynamic>>>>>{};

      for (final date in arrangementsToProcess.keys) {
        developer.log('\nProcessing date: $date');
        final sessions = arrangementsToProcess[date]!;
        arrangementsByDateAndSession[date] = {};

        for (final session in sessions.keys) {
          developer.log('  Processing session: $session');
          final halls = sessions[session]!;
          arrangementsByDateAndSession[date]![session] = {};

          // Group by hall
          for (final hallId in halls.keys) {
            final students = halls[hallId]!;
            arrangementsByDateAndSession[date]![session]![hallId] = students;
            developer.log('    Hall $hallId: ${students.length} students');
          }
        }
      }

      // Process each date and session
      for (final date in arrangementsByDateAndSession.keys) {
        final sessions = arrangementsByDateAndSession[date]!;
        developer.log('\nGenerating PDF pages for date: $date');

        for (final session in sessions.keys) {
          final halls = sessions[session]!;
          if (halls.isEmpty) {
            developer.log('  No halls for session: $session');
            continue;
          }

          developer.log('  Generating pages for session: $session');
          developer.log('  Number of halls: ${halls.length}');

          final examsInSession = widget.exams
              .where((e) =>
                  e['exam_date'].toString().split(' ')[0] == date &&
                  e['session'] == session)
              .toList();

          developer.log('  Exams in session: ${examsInSession.length}');
          developer.log(
              '  Exam details: ${examsInSession.map((e) => '${e['course_id']} - ${e['course_name']}').join(', ')}');

          // Add page for this date and session (containing all halls)
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (context) {
                final pages = <pw.Widget>[];
                developer.log('  Building PDF page content');

                // Header section
                pages.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 1),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Examination Seating Arrangement',
                          style: headerStyle,
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Date: ${DateFormat('MMM d, y').format(DateTime.parse(date))}',
                          style: normalStyle,
                        ),
                        pw.Text(
                          'Session: ${session == 'FN' ? 'Morning' : 'Afternoon'}',
                          style: normalStyle,
                        ),
                        pw.Text(
                          'Time: ${examsInSession.first['time']}',
                          style: normalStyle,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Exams: ${examsInSession.map((e) => '${e['course_id']} - ${e['course_name']}').join(', ')}',
                          style: smallStyle,
                        ),
                      ],
                    ),
                  ),
                );

                pages.add(pw.SizedBox(height: 16));

                // Process each hall vertically
                for (final hallId in halls.keys) {
                  final students = halls[hallId]!;
                  developer.log(
                      '    Processing hall $hallId with ${students.length} students');

                  final hall = _halls.firstWhere(
                    (h) => h['hall_id'] == hallId,
                    orElse: () {
                      developer
                          .log('    ERROR: Hall $hallId not found in _halls!');
                      return {
                        'hall_id': hallId,
                        'no_of_rows': 0,
                        'no_of_columns': 0
                      };
                    },
                  );

                  final rows = hall['no_of_rows'] as int;
                  final cols = hall['no_of_columns'] as int;
                  developer.log('    Hall dimensions: ${rows}x$cols');

                  if (rows == 0 || cols == 0) {
                    developer
                        .log('    ERROR: Invalid hall dimensions for $hallId');
                    continue;
                  }

                  // Calculate optimal cell dimensions
                  final pageWidth = PdfPageFormat.a4.availableWidth - 40;
                  final cellWidth = math.min(30.0, pageWidth / cols);
                  final cellHeight = math.min(25.0, 400 / rows);
                  const cellPadding = 2.0;

                  developer.log(
                      '    Cell dimensions: ${cellWidth}x$cellHeight, padding: $cellPadding');

                  // Hall header
                  pages.add(
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      color: PdfColors.grey200,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text('Hall: $hallId', style: headerStyle),
                        ],
                      ),
                    ),
                  );

                  pages.add(pw.SizedBox(height: 8));

                  // Create seating grid
                  final tableRows = List<pw.TableRow>.generate(rows, (row) {
                    return pw.TableRow(
                      children: List<pw.Widget>.generate(cols, (col) {
                        final student = students.firstWhere(
                          (s) => s['row_no'] == row && s['column_no'] == col,
                          orElse: () => <String, dynamic>{},
                        );
                        final seatNumber = row * cols + col + 1;

                        if (student.isNotEmpty) {
                          developer.log(
                              'Cell content for S$seatNumber: ${student['student_reg_no']}');
                        }

                        return pw.Container(
                          height: cellHeight,
                          width: cellWidth,
                          padding: pw.EdgeInsets.all(cellPadding),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 0.5),
                          ),
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text('S$seatNumber', style: smallStyle),
                              if (student.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text(
                                  student['student_reg_no'].toString(),
                                  style: normalStyle,
                                  textAlign: pw.TextAlign.center,
                                ),
                                pw.SizedBox(height: 1),
                                pw.Text(
                                  student['course_code'].toString(),
                                  style: smallStyle,
                                  textAlign: pw.TextAlign.center,
                                ),
                                if (student['is_supplementary'] == true)
                                  pw.Text(
                                    '(S)',
                                    style: smallStyle,
                                    textAlign: pw.TextAlign.center,
                                  ),
                              ],
                            ],
                          ),
                        );
                      }),
                    );
                  });

                  pages.add(
                    pw.Container(
                      width: pageWidth,
                      child: pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultColumnWidth: pw.FixedColumnWidth(cellWidth),
                        children: [
                          // Add faculty info row
                          pw.TableRow(
                            children: [
                              pw.Container(
                                padding: const pw.EdgeInsets.all(5),
                                decoration: const pw.BoxDecoration(
                                  color: PdfColors.grey200,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      'Faculty: ${_faculty.firstWhere(
                                        (f) =>
                                            f['faculty_id'] ==
                                            widget.hallFacultyMap[
                                                '$hallId|$session|$date'],
                                        orElse: () =>
                                            {'faculty_name': 'Not Assigned'},
                                      )['faculty_name']}',
                                      style: normalStyle,
                                    ),
                                  ],
                                ),
                              ),
                              ...List.generate(cols - 1, (_) => pw.Container()),
                            ],
                          ),
                          ...tableRows,
                        ],
                      ),
                    ),
                  );
                }

                developer.log('  Finished building page content');
                return pages;
              },
            ),
          );
        }
      }

      developer.log('\nSaving PDF document');
      final bytes = await pdf.save();
      developer.log('PDF document saved, size: ${bytes.length} bytes');

      final filename = printAll
          ? 'seating_arrangement_all_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf'
          : 'seating_arrangement_${DateFormat('yyyy_MM_dd').format(_selectedDate!)}_$_selectedSession.pdf';

      if (kIsWeb) {
        // Web platform: Use blob and download
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = filename;
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        developer.log('PDF downloaded in web platform');
      } else {
        // Mobile/Desktop platforms: Use path_provider
        final output = await getTemporaryDirectory();
        final file = File('${output.path}/$filename');
        await file.writeAsBytes(bytes);
        developer.log('PDF saved to: ${file.path}');

        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          developer.log('PDF opened in default viewer');
        } else {
          throw 'Could not open the PDF file';
        }
      }

      developer.log('=== PDF Generation Complete ===');
      setState(() => _isLoading = false);
    } catch (error, stackTrace) {
      developer.log('Error generating PDF:',
          error: error, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Add exam filter widget
  Widget _buildExamFilter(
      Map<String, List<Map<String, dynamic>>> currentSeating) {
    // Get unique exams in current seating
    final exams = currentSeating.values
        .expand((students) => students)
        .map((s) => s['course_code'])
        .toSet()
        .map((courseCode) {
      final exam = widget.exams.firstWhere(
        (e) => e['course_id'] == courseCode,
        orElse: () => <String, dynamic>{},
      );
      return {
        'course_code': courseCode,
        'course_name': exam['course_name'] ?? 'Unknown Course',
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter by Exam',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.02),
                Colors.white.withOpacity(0.02),
                Colors.white,
              ],
              stops: const [0.0, 0.02, 0.98, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstOut,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  selected: _selectedExam == null,
                  showCheckmark: false,
                  label: const Text('All Exams'),
                  onSelected: (_) {
                    setState(() => _selectedExam = null);
                  },
                ),
                const SizedBox(width: 8),
                ...exams.map((exam) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: _selectedExam == exam['course_code'],
                        showCheckmark: false,
                        label: Text(
                          '${exam['course_code']} - ${exam['course_name']}',
                        ),
                        onSelected: (_) {
                          setState(() =>
                              _selectedExam = exam['course_code'] as String);
                        },
                      ),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to get session display name
  String _getSessionDisplayName(String session) {
    switch (session) {
      case 'FN':
        return 'Morning';
      case 'AN':
        return 'Afternoon';
      case 'EN':
        return 'Evening';
      default:
        return session;
    }
  }

  // Add this helper method for stat chips
  Widget _buildStatChip(
      BuildContext context, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // Add this method to show seating arrangement dialog
  void _showSeatingArrangementDialog(
    BuildContext context,
    Map<String, dynamic> hall,
    List<Map<String, dynamic>> students,
    Map<String, dynamic> faculty,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setDialogState) => Scaffold(
            appBar: AppBar(
              title:
                  Text('Hall ${hall['hall_id']} - ${faculty['faculty_name']}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seating Grid
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: _buildSeatingGrid(hall, students),
                    ),
                  ),
                  // Exam Filter Panel
                  SizedBox(
                    width: 250,
                    child: Card(
                      margin: const EdgeInsets.only(left: 16),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Filter by Exam',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilterChip(
                                    selected: _selectedExam == null,
                                    showCheckmark: false,
                                    label: const Text('All Exams'),
                                    onSelected: (_) {
                                      setDialogState(
                                          () => _selectedExam = null);
                                      setState(() {});
                                    },
                                  ),
                                  ...students
                                      .map((s) => s['course_code'])
                                      .toSet()
                                      .map((courseCode) {
                                    final exam = widget.exams.firstWhere(
                                      (e) => e['course_id'] == courseCode,
                                      orElse: () => <String, dynamic>{},
                                    );
                                    return FilterChip(
                                      selected: _selectedExam == courseCode,
                                      showCheckmark: false,
                                      label: Text(
                                        '$courseCode - ${exam['course_name'] ?? 'N/A'}',
                                      ),
                                      onSelected: (_) {
                                        setDialogState(
                                            () => _selectedExam = courseCode);
                                        setState(() {});
                                      },
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Statistics
                              const Divider(),
                              const SizedBox(height: 8),
                              Text(
                                'Statistics',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              _buildStatisticRow(
                                'Total Students',
                                students.length.toString(),
                                Icons.people,
                              ),
                              const SizedBox(height: 8),
                              _buildStatisticRow(
                                'Regular',
                                students
                                    .where(
                                        (s) => !(s['is_supplementary'] as bool))
                                    .length
                                    .toString(),
                                Icons.person,
                              ),
                              const SizedBox(height: 8),
                              _buildStatisticRow(
                                'Supplementary',
                                students
                                    .where((s) => s['is_supplementary'] as bool)
                                    .length
                                    .toString(),
                                Icons.person_outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Add this helper method for statistics in dialog
  Widget _buildStatisticRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  // Helper method to generate spiral positions from center
  List<List<int>> _generateSpiralPositions(int rows, int cols) {
    final positions = <List<int>>[];

    // Start from top-left and move row by row
    for (var row = 0; row < rows; row++) {
      // For even rows, go left to right
      if (row % 2 == 0) {
        for (var col = 0; col < cols; col++) {
          positions.add([row, col]);
        }
      } else {
        // For odd rows, go right to left
        for (var col = cols - 1; col >= 0; col--) {
          positions.add([row, col]);
        }
      }
    }

    return positions;
  }

  // Helper method to get next available position considering spacing rules
  List<int>? _findNextAvailablePosition(
    List<List<String?>> grid,
    String courseId,
    List<List<int>> preferredPositions,
  ) {
    for (final pos in preferredPositions) {
      final row = pos[0];
      final col = pos[1];
      if (grid[row][col] == null && _isSeatSuitable(grid, row, col, courseId)) {
        return [row, col];
      }
    }
    return null;
  }
}
