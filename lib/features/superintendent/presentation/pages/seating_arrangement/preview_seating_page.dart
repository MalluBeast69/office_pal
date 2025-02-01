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
  final List<String> selectedHalls;
  final Map<String, String> hallFacultyMap;

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
  Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>
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
          .in_('hall_id', widget.selectedHalls.toList());
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
      _generateSeatingArrangements();

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

  void _generateSeatingArrangements() {
    // Group exams by date and session
    final examsByDateAndSession =
        <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final exam in widget.exams) {
      final date = exam['exam_date'].toString().split(' ')[0];
      final session = exam['session'] as String;

      examsByDateAndSession[date] ??= {};
      examsByDateAndSession[date]![session] ??= [];
      examsByDateAndSession[date]![session]!.add(exam);
    }

    _seatingArrangements = {};

    // Sort halls by capacity
    final sortedHalls = List<Map<String, dynamic>>.from(_halls)
      ..sort((a, b) => (b['capacity'] as int).compareTo(a['capacity'] as int));

    // Generate seating for each date and session
    for (final date in examsByDateAndSession.keys) {
      _seatingArrangements[date] = {};

      for (final session in examsByDateAndSession[date]!.keys) {
        _seatingArrangements[date]![session] = {};
        final examsInSession = examsByDateAndSession[date]![session]!;

        // Track assigned students to prevent duplicates
        final assignedStudents = <String>{};

        // Group students by exam and sort by supplementary status
        final studentsByExam = <String, List<Map<String, dynamic>>>{};
        for (final exam in examsInSession) {
          final courseId = exam['course_id'] as String;
          final attendingStudents = _students
              .where((s) =>
                  s['course_code'] == courseId &&
                  widget.selectedStudents.contains(s['student_reg_no']) &&
                  !assignedStudents.contains(s['student_reg_no']))
              .toList()
            ..sort((a, b) {
              // Sort by supplementary status first, then by registration number
              if (a['is_supplementary'] != b['is_supplementary']) {
                return a['is_supplementary'] ? 1 : -1;
              }
              return a['student_reg_no'].compareTo(b['student_reg_no']);
            });

          if (attendingStudents.isNotEmpty) {
            studentsByExam[courseId] = attendingStudents;
          }
        }

        if (studentsByExam.isEmpty) continue;

        // Calculate total students
        final totalStudents = studentsByExam.values
            .map((students) => students.length)
            .reduce((a, b) => a + b);

        // Select halls based on total students needed
        final neededHalls = <Map<String, dynamic>>[];
        var remainingStudents = totalStudents;

        for (final hall in sortedHalls) {
          if (remainingStudents <= 0) break;
          neededHalls.add(hall);
          remainingStudents -= hall['capacity'] as int;
        }

        if (neededHalls.isEmpty) continue;

        // Initialize seating arrangements for each hall
        for (final hall in neededHalls) {
          _seatingArrangements[date]![session]![hall['hall_id']] = [];
        }

        // Sort exams by number of students (largest first)
        final sortedExams = studentsByExam.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));

        // Assign students to halls using optimized pattern
        var currentHallIndex = 0;
        var isForward = true;

        for (final examEntry in sortedExams) {
          final courseId = examEntry.key;
          final students = examEntry.value;

          for (final student in students) {
            if (currentHallIndex >= neededHalls.length) {
              currentHallIndex = neededHalls.length - 1;
              isForward = false;
            } else if (currentHallIndex < 0) {
              currentHallIndex = 0;
              isForward = true;
            }

            final hall = neededHalls[currentHallIndex];
            final hallId = hall['hall_id'];
            final rows = hall['no_of_rows'] as int;
            final cols = hall['no_of_columns'] as int;

            // Initialize grid
            final grid = List.generate(
                rows, (_) => List<String?>.filled(cols, null, growable: false),
                growable: false);

            // Fill in existing students
            for (final existingStudent
                in _seatingArrangements[date]![session]![hallId]!) {
              final row = existingStudent['row_no'] as int;
              final col = existingStudent['column_no'] as int;
              grid[row][col] = existingStudent['student_reg_no'] as String;
            }

            // Find next available seat using compact pattern
            bool seatFound = false;

            // Try to fill seats in a compact manner
            for (int row = 0; row < rows && !seatFound; row++) {
              // Use alternating pattern for better distribution
              final colRange = row % 2 == 0
                  ? List.generate(cols, (i) => i)
                  : List.generate(cols, (i) => cols - 1 - i);

              for (final col in colRange) {
                // Skip if this would create too much empty space
                if (row > 0) {
                  int emptySeatsInPreviousRows = 0;
                  for (int r = 0; r < row; r++) {
                    if (grid[r][col] == null) emptySeatsInPreviousRows++;
                  }
                  // Only allow one empty seat gap
                  if (emptySeatsInPreviousRows > 1) continue;
                }

                // Check for empty seats in the current row
                int emptySeatsInCurrentRow = 0;
                for (int c = 0; c < col; c++) {
                  if (grid[row][c] == null) emptySeatsInCurrentRow++;
                }
                // Only allow one empty seat gap in the current row
                if (emptySeatsInCurrentRow > 1) continue;

                if (grid[row][col] == null &&
                    _isSeatSuitable(grid, row, col, courseId, studentsByExam)) {
                  grid[row][col] = student['student_reg_no'];
                  _seatingArrangements[date]![session]![hallId]!.add({
                    'student_reg_no': student['student_reg_no'],
                    'column_no': col,
                    'row_no': row,
                    'is_supplementary': student['is_supplementary'],
                    'student': student['student'],
                    'course_code': student['course_code'],
                  });
                  seatFound = true;
                  assignedStudents.add(student['student_reg_no']);
                  break;
                }
              }
            }

            // If no suitable seat found in compact pattern, try alternative positions
            if (!seatFound) {
              for (int row = 0; row < rows && !seatFound; row++) {
                for (int col = 0; col < cols; col++) {
                  if (grid[row][col] == null &&
                      _isSeatSuitable(
                          grid, row, col, courseId, studentsByExam)) {
                    grid[row][col] = student['student_reg_no'];
                    _seatingArrangements[date]![session]![hallId]!.add({
                      'student_reg_no': student['student_reg_no'],
                      'column_no': col,
                      'row_no': row,
                      'is_supplementary': student['is_supplementary'],
                      'student': student['student'],
                      'course_code': student['course_code'],
                    });
                    seatFound = true;
                    assignedStudents.add(student['student_reg_no']);
                    break;
                  }
                }
              }
            }

            // Move to next hall using snake pattern
            if (isForward) {
              currentHallIndex++;
            } else {
              currentHallIndex--;
            }
          }
        }

        // Remove any halls that ended up with no students
        _seatingArrangements[date]![session]!
            .removeWhere((_, students) => students.isEmpty);
      }
    }
  }

  bool _isSeatSuitable(List<List<String?>> grid, int row, int col,
      String courseId, Map<String, List<Map<String, dynamic>>> studentsByExam) {
    final rows = grid.length;
    final cols = grid[0].length;

    // Define positions to check (only immediate adjacent and diagonal)
    final positions = {
      'adjacent': [
        [-1, 0], // Above
        [1, 0], // Below
        [0, -1], // Left
        [0, 1], // Right
      ],
      'diagonal': [
        [-1, -1], // Top-left
        [-1, 1], // Top-right
        [1, -1], // Bottom-left
        [1, 1], // Bottom-right
      ],
    };

    // Check each position
    for (final entry in positions.entries) {
      for (final pos in entry.value) {
        final newRow = row + pos[0];
        final newCol = col + pos[1];

        if (newRow >= 0 && newRow < rows && newCol >= 0 && newCol < cols) {
          final otherStudentId = grid[newRow][newCol];
          if (otherStudentId != null) {
            // Check if student is from same course
            for (final examEntry in studentsByExam.entries) {
              if (examEntry.key == courseId &&
                  examEntry.value
                      .any((s) => s['student_reg_no'] == otherStudentId)) {
                return false; // Don't allow same course students in adjacent or diagonal positions
              }
            }
          }
        }
      }
    }

    // Check for same exam students in the row and column
    int sameExamInRow = 0;
    int sameExamInCol = 0;

    // Check row
    for (int c = 0; c < cols; c++) {
      if (c != col && grid[row][c] != null) {
        final studentId = grid[row][c];
        for (final entry in studentsByExam.entries) {
          if (entry.key == courseId &&
              entry.value.any((s) => s['student_reg_no'] == studentId)) {
            sameExamInRow++;
            if (sameExamInRow > 0)
              return false; // Only allow one student from same exam in row
          }
        }
      }
    }

    // Check column
    for (int r = 0; r < rows; r++) {
      if (r != row && grid[r][col] != null) {
        final studentId = grid[r][col];
        for (final entry in studentsByExam.entries) {
          if (entry.key == courseId &&
              entry.value.any((s) => s['student_reg_no'] == studentId)) {
            sameExamInCol++;
            if (sameExamInCol > 0)
              return false; // Only allow one student from same exam in column
          }
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
                              Text(
                                'Exam Details',
                                style: const TextStyle(
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
    final facultyId = widget.hallFacultyMap[hallId];
    if (facultyId == null) return;

    final faculty = _faculty.firstWhere((f) => f['faculty_id'] == facultyId);

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

    final currentDateStr = _selectedDate?.toString().split(' ')[0] ??
        _seatingArrangements.keys.first;
    final currentSessions = _seatingArrangements[currentDateStr] ?? {};
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
                                      final date = _seatingArrangements.keys
                                          .elementAt(index);
                                      final isSelected = date == currentDateStr;
                                      return FilterChip(
                                        selected: isSelected,
                                        showCheckmark: false,
                                        onSelected: (bool value) {
                                          setState(() {
                                            _selectedDate =
                                                DateTime.parse(date);
                                            if (_seatingArrangements[date]
                                                    ?.isNotEmpty ??
                                                false) {
                                              _selectedSession =
                                                  _seatingArrangements[date]!
                                                      .keys
                                                      .first;
                                            }
                                            _selectedExam = null;
                                          });
                                        },
                                        label: Text(DateFormat('MMM d, y')
                                            .format(DateTime.parse(date))),
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
                                (f) =>
                                    f['faculty_id'] ==
                                    widget.hallFacultyMap[hallId],
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
                                                          '\n• ${courseCode} - ${exam['course_name'] ?? 'N/A'}',
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

      // Step 1: Prepare seating data
      final seatingData = <Map<String, dynamic>>[];
      final now = DateTime.now().toIso8601String();

      // Keep track of student-exam assignments to prevent duplicates
      final studentExamAssignments =
          <String>{}; // Format: "exam_id:student_reg_no"

      // Step 2: Generate seating data
      for (final date in _seatingArrangements.keys) {
        for (final session in _seatingArrangements[date]!.keys) {
          // Get exams for this date and session
          final examsInSession = widget.exams
              .where((e) =>
                  e['exam_date'].toString().split(' ')[0] == date &&
                  e['session'] == session)
              .toList();

          // Process each exam
          for (final exam in examsInSession) {
            final examId = exam['exam_id'] as String;
            final arrangementId = const Uuid().v4();

            // Process each hall's seating arrangement
            for (final entry in _seatingArrangements[date]![session]!.entries) {
              final hallId = entry.key;
              final students = entry.value;

              // Process each student in the hall
              for (final student in students) {
                final studentRegNo = student['student_reg_no'] as String;
                final studentCourse = _students.firstWhere(
                  (s) => s['student_reg_no'] == studentRegNo,
                  orElse: () => <String, dynamic>{},
                )['course_code'];

                // Only add if student is registered for this exam and hasn't been assigned yet
                final assignmentKey = '$examId:$studentRegNo';
                if (studentCourse == exam['course_id'] &&
                    !studentExamAssignments.contains(assignmentKey)) {
                  studentExamAssignments.add(assignmentKey);

                  seatingData.add({
                    'arrangement_id': arrangementId,
                    'exam_id': examId,
                    'hall_id': hallId,
                    'faculty_id': widget.hallFacultyMap[hallId],
                    'student_reg_no': studentRegNo,
                    'column_no': student['column_no'],
                    'row_no': student['row_no'],
                    'created_at': now,
                    'updated_at': now,
                  });
                }
              }
            }
          }
        }
      }

      if (seatingData.isEmpty) {
        throw Exception('No valid seating arrangements to save');
      }

      // Step 3: Delete existing arrangements for these exams
      final examIds = seatingData.map((d) => d['exam_id'] as String).toSet();
      developer.log('Deleting arrangements for exam IDs: $examIds');

      await Supabase.instance.client
          .from('seating_arr')
          .delete()
          .in_('exam_id', examIds.toList());

      // Step 4: Insert new arrangements in batches
      developer.log('Inserting ${seatingData.length} seating arrangements');

      const batchSize = 50;
      for (var i = 0; i < seatingData.length; i += batchSize) {
        final end = (i + batchSize < seatingData.length)
            ? i + batchSize
            : seatingData.length;
        final batch = seatingData.sublist(i, end);

        await Supabase.instance.client.from('seating_arr').insert(batch);

        // Small delay between batches
        if (end < seatingData.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seating arrangement saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).popUntil(
          (route) =>
              route.settings.name == '/seating_management' || route.isFirst,
        );
      }
    } catch (error) {
      developer.log('Error saving seating arrangement: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving seating arrangement: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _generateAndOpenPDF({required bool printAll}) async {
    try {
      setState(() => _isLoading = true);

      // Create PDF document
      final pdf = pw.Document();

      // Define consistent cell size and styling
      final headerStyle = pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      );
      final normalStyle = const pw.TextStyle(fontSize: 9);
      final smallStyle = const pw.TextStyle(fontSize: 7);

      // Determine which arrangements to process
      final arrangementsToProcess = printAll
          ? _seatingArrangements
          : {
              _selectedDate!.toString().split(' ')[0]: {
                _selectedSession!: _seatingArrangements[
                    _selectedDate!.toString().split(' ')[0]]![_selectedSession]!
              }
            };

      // Group arrangements by date and session
      final arrangementsByDateAndSession =
          <String, Map<String, Map<String, List<Map<String, dynamic>>>>>{};

      for (final date in arrangementsToProcess.keys) {
        final sessions = arrangementsToProcess[date]!;
        arrangementsByDateAndSession[date] = {};

        for (final session in sessions.keys) {
          final halls = sessions[session]!;
          arrangementsByDateAndSession[date]![session] = {};

          // Group by hall
          for (final hallId in halls.keys) {
            final students = halls[hallId]!;
            arrangementsByDateAndSession[date]![session]![hallId] = students;
          }
        }
      }

      // Process each date and session
      for (final date in arrangementsByDateAndSession.keys) {
        final sessions = arrangementsByDateAndSession[date]!;

        for (final session in sessions.keys) {
          final halls = sessions[session]!;
          if (halls.isEmpty) continue;

          final examsInSession = widget.exams
              .where((e) =>
                  e['exam_date'].toString().split(' ')[0] == date &&
                  e['session'] == session)
              .toList();

          // Add page for this date and session (containing all halls)
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (context) {
                final pages = <pw.Widget>[];

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
                          'Date: ${DateFormat('MMMM d, y').format(DateTime.parse(date))}',
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
                  final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
                  final rows = hall['no_of_rows'] as int;
                  final cols = hall['no_of_columns'] as int;

                  // Calculate optimal cell dimensions
                  final pageWidth = PdfPageFormat.a4.availableWidth - 40;
                  final cellWidth = pageWidth / cols;
                  final cellHeight =
                      math.min(30.0, 400 / rows); // Compact layout
                  final double cellPadding = cellWidth < 30 ? 2.0 : 4.0;

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
                          pw.Text('Hall: ${hall['hall_id']}',
                              style: headerStyle),
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
                              pw.Text(
                                'S$seatNumber',
                                style: smallStyle,
                                textAlign: pw.TextAlign.center,
                              ),
                              if (student.isNotEmpty) ...[
                                pw.SizedBox(height: cellHeight > 20 ? 2 : 1),
                                pw.Text(
                                  student['student_reg_no'].toString(),
                                  style: normalStyle,
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
                        children: tableRows,
                      ),
                    ),
                  );

                  pages.add(pw.SizedBox(height: 16));
                }

                return pages;
              },
            ),
          );
        }
      }

      // Save PDF and handle download based on platform
      final bytes = await pdf.save();
      final filename = printAll
          ? 'seating_arrangement_all_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf'
          : 'seating_arrangement_${DateFormat('yyyy_MM_dd').format(_selectedDate!)}_${_selectedSession}.pdf';

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
      } else {
        // Mobile/Desktop platforms: Use path_provider
        final output = await getTemporaryDirectory();
        final file = File('${output.path}/$filename');
        await file.writeAsBytes(bytes);

        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          throw 'Could not open the PDF file';
        }
      }

      setState(() => _isLoading = false);
    } catch (error) {
      developer.log('Error generating PDF: $error');
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
        'course_name': exam['course_name'] ?? 'N/A',
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
                          style: TextStyle(
                            fontSize: Theme.of(context)
                                .textTheme
                                .bodyMedium!
                                .fontSize,
                          ),
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
                                        '${courseCode} - ${exam['course_name'] ?? 'N/A'}',
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
}
