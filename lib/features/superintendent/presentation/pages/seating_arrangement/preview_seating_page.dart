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

  // Add debug logging
  void _logSeatingArrangements() {
    developer.log('Seating Arrangements: $_seatingArrangements');
    if (_selectedDate != null) {
      developer.log('Selected Date: $_selectedDate');
      final dateStr = _selectedDate.toString().split(' ')[0];
      developer.log('Date Sessions: ${_seatingArrangements[dateStr]}');
      if (_selectedSession != null) {
        developer.log('Selected Session: $_selectedSession');
        developer.log(
            'Session Halls: ${_seatingArrangements[dateStr]?[_selectedSession]}');
      }
    }
  }

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

      // Load students data
      final studentsResponse = await Supabase.instance.client
          .from('registered_students')
          .select()
          .in_('student_reg_no', widget.selectedStudents.toList())
          .in_('course_code', widget.exams.map((e) => e['course_id']).toList());
      _students = List<Map<String, dynamic>>.from(studentsResponse);

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

      _logSeatingArrangements(); // Debug log

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error) {
      developer.log('Error loading data: $error');
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

        // Group students by exam
        final studentsByExam = <String, List<String>>{};
        for (final exam in examsInSession) {
          final courseId = exam['course_id'] as String;
          final attendingStudents = _students
              .where((s) =>
                  s['course_code'] == courseId &&
                  widget.selectedStudents.contains(s['student_reg_no']))
              .map((s) => s['student_reg_no'] as String)
              .toList();

          if (attendingStudents.isNotEmpty) {
            studentsByExam[courseId] = attendingStudents;
          }
        }

        if (studentsByExam.isEmpty) continue;

        // Calculate total students
        final totalStudents = studentsByExam.values
            .fold(0, (sum, students) => sum + students.length);

        // Calculate minimum number of halls needed
        int totalRequiredCapacity = totalStudents;
        final neededHalls = <Map<String, dynamic>>[];
        int currentCapacity = 0;

        // First, find minimum halls needed based on total capacity
        for (final hall in sortedHalls) {
          if (currentCapacity < totalRequiredCapacity) {
            neededHalls.add(hall);
            currentCapacity += hall['capacity'] as int;
          } else {
            break;
          }
        }

        // Calculate students per hall (try to distribute evenly)
        final studentsPerHall = (totalStudents / neededHalls.length).ceil();

        // Initialize seating grid for each hall
        final hallGrids = <String, List<List<String?>>>{};
        for (final hall in neededHalls) {
          final rows = hall['no_of_rows'] as int;
          final cols = hall['no_of_columns'] as int;
          hallGrids[hall['hall_id']] = List.generate(
            rows,
            (_) => List.filled(cols, null),
          );
          _seatingArrangements[date]![session]![hall['hall_id']] = [];
        }

        // Prepare all students and shuffle them
        final allStudents = studentsByExam.entries.expand((entry) {
          return entry.value.map((studentId) => {
                'student_id': studentId,
                'course_id': entry.key,
              });
        }).toList()
          ..shuffle();

        // Distribute students evenly across halls
        int currentHallIndex = 0;
        int studentsInCurrentHall = 0;

        for (final student in allStudents) {
          var hall = neededHalls[currentHallIndex];
          var hallId = hall['hall_id'];
          var grid = hallGrids[hallId]!;
          var rows = hall['no_of_rows'] as int;
          var cols = hall['no_of_columns'] as int;

          // Find next available seat in current hall
          bool seatFound = false;
          for (int row = 0; row < rows && !seatFound; row++) {
            for (int col = 0; col < cols && !seatFound; col++) {
              if (grid[row][col] == null &&
                  _isSeatSuitable(grid, row, col,
                      student['course_id'] as String, studentsByExam)) {
                grid[row][col] = student['student_id'];
                _seatingArrangements[date]![session]![hallId]!.add({
                  'student_reg_no': student['student_id'],
                  'column_no': col,
                  'row_no': row,
                  'is_supplementary': _students.firstWhere(
                        (s) => s['student_reg_no'] == student['student_id'],
                      )['is_reguler'] ==
                      false,
                });
                seatFound = true;
                studentsInCurrentHall++;

                // Move to next hall if we've reached the target number of students for this hall
                if (studentsInCurrentHall >= studentsPerHall &&
                    currentHallIndex < neededHalls.length - 1) {
                  currentHallIndex++;
                  studentsInCurrentHall = 0;
                }
              }
            }
          }

          // If no suitable seat found in current hall, try next hall
          if (!seatFound && currentHallIndex < neededHalls.length - 1) {
            currentHallIndex++;
            studentsInCurrentHall = 0;
          }
        }

        // Remove any halls that ended up with no students
        _seatingArrangements[date]![session]!
            .removeWhere((_, students) => students.isEmpty);
      }

      // Remove any sessions that ended up with no arrangements
      _seatingArrangements[date]!.removeWhere((_, halls) => halls.isEmpty);
    }

    // Remove any dates that ended up with no arrangements
    _seatingArrangements.removeWhere((_, sessions) => sessions.isEmpty);
  }

  // Helper function to check if a seat is suitable
  bool _isSeatSuitable(List<List<String?>> grid, int row, int col,
      String courseId, Map<String, List<String>> studentsByExam) {
    final rows = grid.length;
    final cols = grid[0].length;

    // Check all adjacent seats (including diagonals)
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        if (i == 0 && j == 0) continue;

        final newRow = row + i;
        final newCol = col + j;

        if (newRow >= 0 && newRow < rows && newCol >= 0 && newCol < cols) {
          final adjacentStudent = grid[newRow][newCol];
          if (adjacentStudent != null) {
            // Find the course of the adjacent student
            String? adjacentCourse;
            for (final entry in studentsByExam.entries) {
              if (entry.value.contains(adjacentStudent)) {
                adjacentCourse = entry.key;
                break;
              }
            }

            // Don't allow same course students to sit adjacent (including diagonally)
            if (adjacentCourse == courseId) return false;
          }
        }
      }
    }

    // Also check one more seat away horizontally and vertically
    final checkPositions = [
      [-2, 0], [2, 0], // Two seats vertically
      [0, -2], [0, 2], // Two seats horizontally
    ];

    for (final position in checkPositions) {
      final newRow = row + position[0];
      final newCol = col + position[1];

      if (newRow >= 0 && newRow < rows && newCol >= 0 && newCol < cols) {
        final farStudent = grid[newRow][newCol];
        if (farStudent != null) {
          // Find the course of the far student
          String? farCourse;
          for (final entry in studentsByExam.entries) {
            if (entry.value.contains(farStudent)) {
              farCourse = entry.key;
              break;
            }
          }

          // Don't allow same course students to sit two seats away
          if (farCourse == courseId) return false;
        }
      }
    }

    return true;
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

  Future<void> _generateAndOpenPDF() async {
    try {
      setState(() => _isLoading = true);

      // Create PDF document
      final pdf = pw.Document();

      // Generate seating arrangements for each date and session
      for (final date in _seatingArrangements.keys) {
        final sessions = _seatingArrangements[date]!;

        for (final session in sessions.keys) {
          final currentSeating = sessions[session]!;
          final examsInSession = widget.exams
              .where((e) =>
                  e['exam_date'].toString().split(' ')[0] == date &&
                  e['session'] == session)
              .toList();

          // Skip if no exams in this session
          if (examsInSession.isEmpty) continue;

          // Add session page with seating details
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              build: (context) {
                final pages = <pw.Widget>[];
                final hallChunks = <List<String>>[];
                final selectedHalls = widget.selectedHalls
                    .where(
                        (hallId) => currentSeating[hallId]?.isNotEmpty ?? false)
                    .toList();

                // Split halls into chunks of 2 for side-by-side display
                for (var i = 0; i < selectedHalls.length; i += 2) {
                  if (i + 1 < selectedHalls.length) {
                    hallChunks.add([selectedHalls[i], selectedHalls[i + 1]]);
                  } else {
                    hallChunks.add([selectedHalls[i]]);
                  }
                }

                pages.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Examination Seating Arrangement',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Date: ${DateFormat('MMMM d, y').format(DateTime.parse(date))}',
                        ),
                        pw.Text('Session: $session'),
                        pw.Text('Time: ${examsInSession.first['time']}'),
                      ],
                    ),
                  ),
                );

                pages.add(pw.SizedBox(height: 20));

                // Add hall chunks
                for (final hallPair in hallChunks) {
                  pages.add(
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: hallPair.map((hallId) {
                        final hall =
                            _halls.firstWhere((h) => h['hall_id'] == hallId);
                        final students = currentSeating[hallId] ?? [];

                        // Calculate seat numbers
                        final seatNumbers = <String, int>{};
                        var seatCounter = 1;
                        for (var row = 0; row < hall['no_of_rows']; row++) {
                          for (var col = 0;
                              col < hall['no_of_columns'];
                              col++) {
                            final student = students.firstWhere(
                              (s) =>
                                  s['row_no'] == row && s['column_no'] == col,
                              orElse: () => <String, dynamic>{},
                            );
                            if (student.isNotEmpty) {
                              seatNumbers['${row}_${col}'] = seatCounter++;
                            }
                          }
                        }

                        return pw.Expanded(
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.all(4),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.grey200,
                                    borderRadius: const pw.BorderRadius.all(
                                        pw.Radius.circular(4)),
                                  ),
                                  child: pw.Text(
                                    'Hall: $hallId',
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Table(
                                  border: pw.TableBorder.all(width: 0.5),
                                  children: List.generate(
                                    hall['no_of_rows'] as int,
                                    (row) => pw.TableRow(
                                      children: List.generate(
                                        hall['no_of_columns'] as int,
                                        (col) {
                                          final student = students.firstWhere(
                                            (s) =>
                                                s['row_no'] == row &&
                                                s['column_no'] == col,
                                            orElse: () => <String, dynamic>{},
                                          );

                                          final seatNumber =
                                              seatNumbers['${row}_${col}'];

                                          return pw.Container(
                                            height: 24,
                                            padding: const pw.EdgeInsets.all(2),
                                            alignment: pw.Alignment.center,
                                            child: pw.Stack(
                                              children: [
                                                // Always show seat number
                                                pw.Positioned(
                                                  top: 0,
                                                  right: 0,
                                                  child: pw.Text(
                                                    'S${row * (hall['no_of_columns'] as int) + col + 1}',
                                                    style: const pw.TextStyle(
                                                      fontSize: 6,
                                                      color: PdfColors.blue,
                                                    ),
                                                  ),
                                                ),
                                                if (student.isNotEmpty)
                                                  pw.Center(
                                                    child: pw.Padding(
                                                      padding: const pw
                                                          .EdgeInsets.only(
                                                          top: 6),
                                                      child: pw.Text(
                                                        student['student_reg_no']
                                                            .toString(),
                                                        style:
                                                            const pw.TextStyle(
                                                                fontSize: 8),
                                                        textAlign:
                                                            pw.TextAlign.center,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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

      // Save and open the PDF
      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/seating_arrangement_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not open the PDF file';
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

  @override
  Widget build(BuildContext context) {
    // Early return if no data is available
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

    // Get current seating data safely
    final currentDateStr = _selectedDate?.toString().split(' ')[0] ??
        _seatingArrangements.keys.first;
    final currentSessions = _seatingArrangements[currentDateStr] ?? {};
    final currentSession = _selectedSession ??
        (currentSessions.isNotEmpty ? currentSessions.keys.first : null);
    final currentSeating =
        currentSession != null ? currentSessions[currentSession] ?? {} : {};

    // Calculate statistics
    final totalStudents = currentSeating.values.fold<int>(
      0,
      (sum, students) => sum + (students as List<dynamic>).length,
    );
    final regularStudents = currentSeating.values.fold<int>(
      0,
      (sum, students) =>
          sum +
          (students as List<dynamic>)
              .where((s) => !(s['is_supplementary'] as bool))
              .length,
    );
    final suppStudents = totalStudents - regularStudents;

    // Get exams for current session
    final currentExams = widget.exams
        .where((e) =>
            e['exam_date'].toString().split(' ')[0] == currentDateStr &&
            e['session'] == currentSession)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Seating'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: _generateAndOpenPDF,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showLegend(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top section with date and session selection
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date selection
                      Text(
                        'Exam Date',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _seatingArrangements.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final date =
                                _seatingArrangements.keys.elementAt(index);
                            final isSelected = date == currentDateStr;
                            return FilterChip(
                              selected: isSelected,
                              showCheckmark: false,
                              label: Text(
                                DateFormat('MMM d, y')
                                    .format(DateTime.parse(date)),
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _selectedDate = DateTime.parse(date);
                                  if (_seatingArrangements[date]?.isNotEmpty ??
                                      false) {
                                    _selectedSession =
                                        _seatingArrangements[date]!.keys.first;
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Session selection
                      if (currentSessions.isNotEmpty) ...[
                        Text(
                          'Session',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: currentSessions.keys.map((session) {
                            final isSelected = session == currentSession;
                            return FilterChip(
                              selected: isSelected,
                              showCheckmark: false,
                              label: Text(session),
                              onSelected: (_) {
                                setState(() => _selectedSession = session);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Statistics and exam info
                if (currentSession != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Statistics row
                        Row(
                          children: [
                            _StatCard(
                              icon: Icons.people,
                              label: 'Total Students',
                              value: totalStudents.toString(),
                            ),
                            const SizedBox(width: 8),
                            _StatCard(
                              icon: Icons.school,
                              label: 'Regular',
                              value: regularStudents.toString(),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            _StatCard(
                              icon: Icons.history_edu,
                              label: 'Supplementary',
                              value: suppStudents.toString(),
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Current exams
                        Text(
                          'Exams in this Session',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: currentExams.map((exam) {
                            return Chip(
                              label: Text(
                                '${exam['course_id']} - ${exam['course_name'] ?? 'N/A'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                // Hall-wise seating arrangements
                Expanded(
                  child: currentSeating.isEmpty
                      ? const Center(
                          child:
                              Text('No seating arrangements for this session'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: currentSeating.length,
                          itemBuilder: (context, index) {
                            final hallId = currentSeating.keys.elementAt(index);
                            final students = currentSeating[hallId]!;
                            final hall = _halls
                                .firstWhere((h) => h['hall_id'] == hallId);
                            final faculty = _faculty.firstWhere((f) =>
                                f['faculty_id'] ==
                                widget.hallFacultyMap[hallId]);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Hall header
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Hall: $hallId',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Faculty: ${faculty['faculty_name']}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${students.length} students',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                            Text(
                                              '${students.where((s) => !(s['is_supplementary'] as bool)).length} regular',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            Text(
                                              '${students.where((s) => s['is_supplementary'] as bool).length} supplementary',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Seating grid
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Column(
                                        children: List.generate(
                                          hall['no_of_rows'] as int,
                                          (row) => Row(
                                            children: List.generate(
                                              hall['no_of_columns'] as int,
                                              (col) {
                                                final student =
                                                    students.firstWhere(
                                                  (s) =>
                                                      s['row_no'] == row &&
                                                      s['column_no'] == col,
                                                  orElse: () =>
                                                      <String, dynamic>{},
                                                );

                                                // Calculate seat number based on position
                                                final seatNumber = row *
                                                        (hall['no_of_columns']
                                                            as int) +
                                                    col +
                                                    1;

                                                return Container(
                                                  width: 80,
                                                  height: 60,
                                                  margin:
                                                      const EdgeInsets.all(2),
                                                  decoration: BoxDecoration(
                                                    color: student.isNotEmpty
                                                        ? (student['is_supplementary']
                                                                as bool
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .secondaryContainer
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .primaryContainer)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .surfaceVariant,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: Border.all(
                                                      color: student.isNotEmpty
                                                          ? (student['is_supplementary']
                                                                  as bool
                                                              ? Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .secondary
                                                              : Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .primary)
                                                          : Theme.of(context)
                                                              .colorScheme
                                                              .outline,
                                                    ),
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      // Always show seat number at the top
                                                      Positioned(
                                                        top: 2,
                                                        right: 2,
                                                        child: Text(
                                                          'S$seatNumber',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .labelSmall
                                                                  ?.copyWith(
                                                                    color: Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .primary,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                        ),
                                                      ),
                                                      // Show student info if seat is occupied
                                                      if (student.isNotEmpty)
                                                        Positioned.fill(
                                                          child: Tooltip(
                                                            message:
                                                                '${student['student_reg_no']}\n${_students.firstWhere((s) => s['student_reg_no'] == student['student_reg_no'])['course_code']}',
                                                            child: Center(
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            12),
                                                                child: Text(
                                                                  student['student_reg_no']
                                                                      .toString()
                                                                      .substring(
                                                                          0, 4),
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .labelSmall,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Save Arrangement'),
          onPressed: _isSaving ? null : _saveSeatingArrangement,
        ),
      ),
    );
  }

  void _showLegend(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Legend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendItem(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderColor: Theme.of(context).colorScheme.primary,
              label: 'Regular Student',
            ),
            const SizedBox(height: 8),
            _LegendItem(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderColor: Theme.of(context).colorScheme.secondary,
              label: 'Supplementary Student',
            ),
            const SizedBox(height: 8),
            _LegendItem(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderColor: Theme.of(context).colorScheme.outline,
              label: 'Empty Seat',
            ),
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
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color?.withOpacity(0.1) ??
              Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color ?? Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final String label;

  const _LegendItem({
    required this.color,
    required this.borderColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
