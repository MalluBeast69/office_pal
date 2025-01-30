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
      final date = exam['exam_date']
          .toString()
          .split(' ')[0]; // Ensure date format is consistent
      final session = exam['session'] as String;

      examsByDateAndSession[date] ??= {};
      examsByDateAndSession[date]![session] ??= [];
      examsByDateAndSession[date]![session]!.add(exam);
    }

    // Initialize seating arrangements
    _seatingArrangements = {};

    // Sort halls by capacity
    final sortedHalls = List<Map<String, dynamic>>.from(_halls)
      ..sort((a, b) => (b['capacity'] as int).compareTo(a['capacity'] as int));

    // Generate seating for each date and session
    for (final date in examsByDateAndSession.keys) {
      _seatingArrangements[date] = {};

      for (final session in examsByDateAndSession[date]!.keys) {
        _seatingArrangements[date]![session] = {};

        // Initialize halls
        for (final hall in sortedHalls) {
          _seatingArrangements[date]![session]![hall['hall_id']] = [];
        }

        final examsInSession = examsByDateAndSession[date]![session]!;

        // Get students for these exams
        final studentsInSession = _students
            .where((s) =>
                examsInSession.any((e) => e['course_id'] == s['course_code']))
            .toList();

        // Group students by regular/supplementary
        final regularStudents = studentsInSession
            .where((s) => s['is_reguler'] == true)
            .map((s) => s['student_reg_no'] as String)
            .toList();
        final suppStudents = studentsInSession
            .where((s) => s['is_reguler'] == false)
            .map((s) => s['student_reg_no'] as String)
            .toList();

        int currentHallIndex = 0;
        int currentColumn = 0;
        int currentRow = 0;

        // Helper function to add student to current position
        void addStudent(String studentRegNo, bool isSupplementary) {
          if (currentHallIndex >= sortedHalls.length) return;

          final hall = sortedHalls[currentHallIndex];
          final hallId = hall['hall_id'];
          final columns = hall['no_of_columns'] as int;
          final rows = hall['no_of_rows'] as int;

          _seatingArrangements[date]![session]![hallId]!.add({
            'student_reg_no': studentRegNo,
            'column_no': currentColumn,
            'row_no': currentRow,
            'is_supplementary': isSupplementary,
          });

          // Move to next position
          currentRow++;
          if (currentRow >= rows) {
            currentRow = 0;
            currentColumn++;
            if (currentColumn >= columns) {
              currentColumn = 0;
              currentHallIndex++;
            }
          }
        }

        // First, assign regular students
        for (var student in regularStudents) {
          addStudent(student, false);
        }

        // Then, assign supplementary students in new columns
        if (suppStudents.isNotEmpty && currentHallIndex < sortedHalls.length) {
          currentRow = 0;
          currentColumn = ((currentColumn + 1) %
              (sortedHalls[currentHallIndex]['no_of_columns'] as int));

          for (var student in suppStudents) {
            addStudent(student, true);
          }
        }
      }
    }

    developer.log('Generated seating arrangements: $_seatingArrangements');
  }

  Future<void> _saveSeatingArrangement() async {
    try {
      setState(() => _isSaving = true);

      final seatingData = <Map<String, dynamic>>[];

      // Prepare data for each exam and student
      for (final date in _seatingArrangements.keys) {
        for (final session in _seatingArrangements[date]!.keys) {
          // Get exams for this date and session
          final examsInSession = widget.exams
              .where((e) => e['exam_date'] == date && e['session'] == session)
              .toList();

          for (final exam in examsInSession) {
            for (final entry in _seatingArrangements[date]![session]!.entries) {
              final hallId = entry.key;
              final students = entry.value;

              for (final student in students) {
                // Only add seating for students registered in this exam
                final isRegistered = _students.any((s) =>
                    s['student_reg_no'] == student['student_reg_no'] &&
                    s['course_code'] == exam['course_id']);

                if (isRegistered) {
                  seatingData.add({
                    'exam_id': exam['exam_id'],
                    'hall_id': hallId,
                    'faculty_id': widget.hallFacultyMap[hallId],
                    'student_reg_no': student['student_reg_no'],
                    'column_no': student['column_no'],
                    'row_no': student['row_no'],
                  });
                }
              }
            }
          }
        }
      }

      // Insert into database
      await Supabase.instance.client.from('seating_arr').insert(seatingData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seating arrangement saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back to seating management page
        Navigator.of(context).popUntil((route) =>
            route.settings.name == '/seating_management' || route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving seating arrangement: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _generateAndOpenPDF() async {
    try {
      setState(() => _isLoading = true);

      // Create PDF document
      final pdf = pw.Document();

      // Add title page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Examination Seating Arrangement',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Generated on: ${DateFormat('MMMM d, y').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Important Instructions:',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                    '1. Please arrive at least 30 minutes before the exam.'),
                pw.Text('2. Bring your student ID card and hall ticket.'),
                pw.Text('3. Check your seating location before the exam day.'),
                pw.Text(
                    '4. Mobile phones and electronic devices are not allowed.'),
              ],
            );
          },
        ),
      );

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

          // Add session title page
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Date: ${DateFormat('MMMM d, y').format(DateTime.parse(date))}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Session: $session',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      'Hall-wise Seating Arrangement',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),
          );

          // Add hall-wise seating arrangements
          for (final hallId in widget.selectedHalls) {
            final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
            final students = currentSeating[hallId] ?? [];

            pdf.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                build: (context) {
                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Hall header
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
                              'Hall: $hallId',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Date: ${DateFormat('MMMM d, y').format(DateTime.parse(date))}',
                            ),
                            pw.Text('Session: $session'),
                            pw.Text('Time: ${examsInSession.first['time']}'),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 20),
                      // Seating grid
                      pw.Table(
                        border: pw.TableBorder.all(),
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

                                return pw.Container(
                                  height: 40,
                                  padding: const pw.EdgeInsets.all(4),
                                  alignment: pw.Alignment.center,
                                  decoration: pw.BoxDecoration(
                                    border:
                                        pw.Border.all(color: PdfColors.black),
                                  ),
                                  child: student.isNotEmpty
                                      ? pw.Column(
                                          mainAxisAlignment:
                                              pw.MainAxisAlignment.center,
                                          children: [
                                            pw.Text(
                                              student['student_reg_no']
                                                  .toString(),
                                              style: const pw.TextStyle(
                                                  fontSize: 8),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                            pw.Text(
                                              'Seat ${(row * (hall['no_of_columns'] as int) + col + 1)}',
                                              style: const pw.TextStyle(
                                                  fontSize: 7),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                          ],
                                        )
                                      : pw.Container(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        'Note: This seating arrangement is subject to change. Please verify your seat on the exam day.',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }
        }
      }

      // Save the PDF
      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/seating_arrangement_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      // Open the PDF using the platform's default viewer
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Seating'),
        actions: [
          // Export PDF button
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: _generateAndOpenPDF,
          ),
          // Legend button
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Legend'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Regular Student'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Supplementary Student'),
                        ],
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
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Calendar and session selector
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date selector
                      Text(
                        'Select Date',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _seatingArrangements.keys.map((date) {
                            final isSelected = currentDateStr == date;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                selected: isSelected,
                                label: Text(DateFormat('MMM d, y')
                                    .format(DateTime.parse(date))),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedDate = DateTime.parse(date);
                                      if (_seatingArrangements[date]
                                              ?.isNotEmpty ??
                                          false) {
                                        _selectedSession =
                                            _seatingArrangements[date]!
                                                .keys
                                                .first;
                                      }
                                    });
                                    _logSeatingArrangements(); // Debug log
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Session selector
                      if (currentSessions.isNotEmpty) ...[
                        Text(
                          'Select Session',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: currentSessions.keys.map((session) {
                              final isSelected = currentSession == session;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  selected: isSelected,
                                  label: Text(session),
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(
                                          () => _selectedSession = session);
                                      _logSeatingArrangements(); // Debug log
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Statistics
                      if (currentSession != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.analytics, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Statistics',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Students: $totalStudents'),
                                        Text('Regular: $regularStudents'),
                                        Text('Supplementary: $suppStudents'),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'Halls Used: ${currentSeating.keys.length}'),
                                        Text(
                                            'Date: ${DateFormat('MMM d, y').format(DateTime.parse(currentDateStr))}'),
                                        Text('Session: $currentSession'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Exam details
                      if (currentSession != null) ...[
                        Text(
                          'Exams',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ...widget.exams
                            .where((e) =>
                                e['exam_date'].toString().split(' ')[0] ==
                                    currentDateStr &&
                                e['session'] == currentSession)
                            .map((exam) => Card(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  child: ListTile(
                                    title: Text(exam['course_id']),
                                    subtitle: Text(
                                        '${exam['time']}, ${exam['duration']} mins'),
                                    leading: Icon(
                                      Icons.book,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )),
                      ],
                    ],
                  ),
                ),
                // Hall-wise seating arrangement
                if (currentSession != null)
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.selectedHalls.length,
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final hallId = widget.selectedHalls[index];
                        final hall =
                            _halls.firstWhere((h) => h['hall_id'] == hallId);
                        final faculty = _faculty.firstWhere((f) =>
                            f['faculty_id'] == widget.hallFacultyMap[hallId]);
                        final students = currentSeating[hallId] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                          Text(
                                              'Faculty: ${faculty['faculty_name']}'),
                                          Text(
                                            'Capacity: ${hall['capacity']} (${hall['no_of_columns']} columns × ${hall['no_of_rows']} rows)',
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
                                              .titleMedium!
                                              .copyWith(
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
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: List.generate(
                                    hall['no_of_rows'] as int,
                                    (row) => Row(
                                      children: List.generate(
                                        hall['no_of_columns'] as int,
                                        (col) {
                                          final student = students.firstWhere(
                                            (s) =>
                                                s['row_no'] == row &&
                                                s['column_no'] == col,
                                            orElse: () => <String, dynamic>{},
                                          );

                                          final isSupplementary =
                                              student.isNotEmpty
                                                  ? student['is_supplementary']
                                                      as bool
                                                  : false;

                                          return Expanded(
                                            child: Container(
                                              height: 60,
                                              margin: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: student.isNotEmpty
                                                    ? isSupplementary
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .secondaryContainer
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: student.isNotEmpty
                                                      ? isSupplementary
                                                          ? Theme.of(context)
                                                              .colorScheme
                                                              .secondary
                                                          : Theme.of(context)
                                                              .colorScheme
                                                              .primary
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .outline,
                                                ),
                                              ),
                                              child: student.isNotEmpty
                                                  ? Tooltip(
                                                      message:
                                                          '${student['student_reg_no']}\n${_students.firstWhere((s) => s['student_reg_no'] == student['student_reg_no'])['course_code']}',
                                                      child: Center(
                                                        child: Text(
                                                          student['student_reg_no']
                                                              .toString()
                                                              .substring(0, 4),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .labelSmall,
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          );
                                        },
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
                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.check),
                          label:
                              Text(_isSaving ? 'Saving...' : 'Confirm Seating'),
                          onPressed: _isSaving ? null : _saveSeatingArrangement,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
