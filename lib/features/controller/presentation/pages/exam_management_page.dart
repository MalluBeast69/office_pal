import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/providers/course_provider.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/presentation/widgets/excel_preview_dialog.dart';
import 'package:office_pal/features/controller/utils/exam_timetable_excel.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;

enum ExamSortOption {
  date('Date'),
  course('Course'),
  session('Session');

  final String label;
  const ExamSortOption(this.label);
}

class ExamManagementPage extends ConsumerStatefulWidget {
  const ExamManagementPage({super.key});

  @override
  ConsumerState<ExamManagementPage> createState() => _ExamManagementPageState();
}

class _ExamManagementPageState extends ConsumerState<ExamManagementPage> {
  String _searchQuery = '';
  ExamSortOption _sortOption = ExamSortOption.date;
  bool _sortAscending = true;
  bool _showToday = true;
  bool _showUpcoming = true;
  bool _showPast = true;

  List<Map<String, dynamic>> _filterAndSortExams(
      List<Map<String, dynamic>> exams) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return exams.where((exam) {
      // Search filter
      final course = exam['course'] as Map<String, dynamic>?;
      if (course == null) return false;

      final courseCode = course['course_code']?.toString().toLowerCase() ?? '';
      final courseName = course['course_name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();

      if (!courseCode.contains(searchLower) &&
          !courseName.contains(searchLower)) {
        return false;
      }

      // Date filters
      final examDate = DateTime.parse(exam['exam_date']);
      final examDay = DateTime(examDate.year, examDate.month, examDate.day);

      final isToday = examDay.isAtSameMomentAs(today);
      final isUpcoming = examDay.isAfter(today);
      final isPast = examDay.isBefore(today);

      if (isToday && !_showToday) return false;
      if (isUpcoming && !_showUpcoming) return false;
      if (isPast && !_showPast) return false;

      return true;
    }).toList()
      ..sort((a, b) {
        switch (_sortOption) {
          case ExamSortOption.date:
            final aDate = DateTime.parse(a['exam_date']);
            final bDate = DateTime.parse(b['exam_date']);
            return _sortAscending
                ? aDate.compareTo(bDate)
                : bDate.compareTo(aDate);
          case ExamSortOption.course:
            final aCourse =
                (a['course'] as Map<String, dynamic>?)?['course_code']
                        ?.toString() ??
                    '';
            final bCourse =
                (b['course'] as Map<String, dynamic>?)?['course_code']
                        ?.toString() ??
                    '';
            return _sortAscending
                ? aCourse.compareTo(bCourse)
                : bCourse.compareTo(aCourse);
          case ExamSortOption.session:
            final aSession = a['session']?.toString() ?? '';
            final bSession = b['session']?.toString() ?? '';
            return _sortAscending
                ? aSession.compareTo(bSession)
                : bSession.compareTo(aSession);
        }
      });
  }

  Widget _buildExamStatusBadge(DateTime examDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDay = DateTime(examDate.year, examDate.month, examDate.day);

    if (examDay.isAtSameMomentAs(today)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
            SizedBox(width: 4),
            Text('Today', style: TextStyle(color: Colors.orange)),
          ],
        ),
      );
    } else if (examDay.isBefore(today)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 16, color: Colors.grey),
            SizedBox(width: 4),
            Text('Past', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text('Upcoming', style: TextStyle(color: Colors.green)),
          ],
        ),
      );
    }
  }

  Future<void> _generateExcelForAllExams(
      BuildContext context, WidgetRef ref) async {
    try {
      final examRepository = ref.read(examRepositoryProvider);
      final courseRepository = ref.read(courseRepositoryProvider);

      final exams = await examRepository.generateExcelData();
      final courses = await courseRepository.getCourses();

      await showDialog(
        context: context,
        builder: (context) => ExcelPreviewDialog(
          excelBytes: ExamTimetableExcel.generate(
            exams.map((e) => Exam.fromJson(e)).toList(),
            courses.map((c) => Course.fromJson(c)).toList(),
          ),
          fileName:
              'all_exams_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating Excel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showPostponementDialog(
      BuildContext context, WidgetRef ref, Exam exam) async {
    print('Opening postponement dialog for exam: ${exam.examId}');
    DateTime? selectedDate;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Postpone Exam'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Current Date: ${DateFormat('MMM d, y').format(exam.examDate)}'),
              const SizedBox(height: 16),
              Text(
                selectedDate == null
                    ? 'No date selected'
                    : 'New Date: ${DateFormat('MMM d, y').format(selectedDate!)}',
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    print('Selected new date: $picked');
                    setState(() => selectedDate = picked);
                  }
                },
                child: const Text('Select New Date'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('Postponement cancelled');
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedDate == null
                  ? null
                  : () {
                      print('Confirming postponement to: $selectedDate');
                      Navigator.of(context).pop({'date': selectedDate});
                    },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      try {
        print(
            'Attempting to postpone exam ${exam.examId} to ${result['date']}');
        final repository = ref.read(examRepositoryProvider);
        await repository.postponeExam(
          exam.examId,
          result['date'],
          '', // Empty reason since we don't store it
        );
        print('Exam postponed successfully');
        ref.refresh(examsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam postponed successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e, stackTrace) {
        print('Error postponing exam: $e');
        print('Stack trace: $stackTrace');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error postponing exam: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, Exam exam) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exam'),
        content: Text(
            'Are you sure you want to delete the exam for ${exam.courseId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        final repository = ref.read(examRepositoryProvider);
        await repository.deleteExam(exam.examId);
        ref.refresh(examsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting exam: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Add listener to refresh exams when page gains focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(examsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider);
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chair),
            tooltip: 'Generate Seating',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Seating arrangement feature coming soon'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import Excel',
            onPressed: () => _importFromExcel(context),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Generate Excel',
            onPressed: () => _generateExcelForAllExams(context, ref),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by course code or name',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // Sort options
                    DropdownButton<ExamSortOption>(
                      value: _sortOption,
                      items: ExamSortOption.values.map((option) {
                        return DropdownMenuItem(
                          value: option,
                          child: Text('Sort by ${option.label}'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortOption = value);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(_sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward),
                      onPressed: () =>
                          setState(() => _sortAscending = !_sortAscending),
                      tooltip: _sortAscending ? 'Ascending' : 'Descending',
                    ),
                    const SizedBox(width: 16),
                    // Filter chips
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.orange),
                          SizedBox(width: 4),
                          Text('Today'),
                        ],
                      ),
                      selected: _showToday,
                      selectedColor: Colors.orange.withOpacity(0.2),
                      checkmarkColor: Colors.orange,
                      onSelected: (value) => setState(() => _showToday = value),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_available,
                              size: 16, color: Colors.green),
                          SizedBox(width: 4),
                          Text('Upcoming'),
                        ],
                      ),
                      selected: _showUpcoming,
                      selectedColor: Colors.green.withOpacity(0.2),
                      checkmarkColor: Colors.green,
                      onSelected: (value) =>
                          setState(() => _showUpcoming = value),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 16, color: Colors.grey),
                          SizedBox(width: 4),
                          Text('Past'),
                        ],
                      ),
                      selected: _showPast,
                      selectedColor: Colors.grey.withOpacity(0.2),
                      checkmarkColor: Colors.grey,
                      onSelected: (value) => setState(() => _showPast = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: examsAsync.when(
        data: (exams) {
          if (exams.isEmpty) {
            return const Center(
              child: Text('No exams scheduled yet'),
            );
          }

          return coursesAsync.when(
            data: (courses) {
              final courseMap = {
                for (var course in courses) course['course_code']: course
              };

              final filteredExams = _filterAndSortExams(exams);

              return ListView.builder(
                itemCount: filteredExams.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final exam = Exam.fromJson(filteredExams[index]);
                  final course = courseMap[exam.courseId];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                                '${exam.courseId} - ${course?['course_name'] ?? 'Unknown Course'}'),
                          ),
                          _buildExamStatusBadge(exam.examDate),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Department: ${course?['dept_id'] ?? 'Unknown Dept'}'),
                          Text(
                              'Date: ${DateFormat('MMM d, y').format(exam.examDate)}'),
                          Text('Session: ${exam.session}, Time: ${exam.time}'),
                          Text('Duration: ${exam.duration} mins'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            tooltip: 'Postpone',
                            onPressed: () =>
                                _showPostponementDialog(context, ref, exam),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete',
                            onPressed: () =>
                                _showDeleteConfirmation(context, ref, exam),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading courses: $error'),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading exams: $error'),
        ),
      ),
    );
  }

  Future<void> _importFromExcel(BuildContext context) async {
    try {
      print('Starting Excel import process...');
      print('Opening file picker...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
        onFileLoading: (status) => print('File loading status: $status'),
      );

      if (result == null) {
        print('No file selected');
        return;
      }

      final file = result.files.first;
      print('File selected: ${file.name}');
      print('File size: ${file.size} bytes');
      print('File extension: ${file.extension}');
      print('Bytes available: ${file.bytes != null}');

      if (file.bytes == null) {
        throw Exception('Could not read file data');
      }

      print('First few bytes: ${file.bytes!.take(10).toList()}');
      print('Attempting to decode Excel file...');

      try {
        final excelFile = excel.Excel.decodeBytes(file.bytes!);
        print('Excel file decoded successfully');
        print('Available sheets: ${excelFile.sheets.keys.join(', ')}');

        final defaultSheet = excelFile.getDefaultSheet();
        print('Default sheet: $defaultSheet');

        final sheet = excelFile.sheets[defaultSheet];
        if (sheet == null) {
          throw Exception('Excel file has no sheets');
        }

        print('Sheet found. Row count: ${sheet.rows.length}');
        if (sheet.rows.isNotEmpty) {
          print(
              'First row headers: ${sheet.rows.first.map((cell) => cell?.value).join(', ')}');
        }

        List<Map<String, dynamic>> validExams = [];
        List<Map<String, dynamic>> invalidExams = [];
        bool isFirstRow = true;

        // Get list of valid course IDs
        final courseRepository = ref.read(courseRepositoryProvider);
        final courses = await courseRepository.getCourses();
        final validCourseIds =
            courses.map((c) => c['course_code'].toString()).toSet();

        for (var row in sheet.rows) {
          if (isFirstRow) {
            isFirstRow = false;
            continue;
          }

          if (row.isEmpty || row[0]?.value == null) {
            print('Skipping empty row');
            continue;
          }

          try {
            print(
                'Processing row values: ${row.map((cell) => cell?.value).join(', ')}');

            final courseId = row[0]!.value.toString().trim();
            final dateStr = row[1]!.value.toString().trim();
            final session = row[2]!.value.toString().trim().toUpperCase();
            final time = row[3]!.value.toString().trim();
            final duration = int.parse(row[4]!.value.toString().trim());

            print(
                'Parsed row: CourseID=$courseId, Date=$dateStr, Session=$session, Time=$time, Duration=$duration');

            final examDate = DateTime.parse(dateStr);
            final examId = _generateExamId(courseId);
            final now = DateTime.now().toIso8601String();

            final exam = {
              'exam_id': examId,
              'course_id': courseId,
              'exam_date': examDate.toIso8601String(),
              'session': session,
              'time': time,
              'duration': duration,
              'created_at': now,
              'updated_at': now,
            };

            // Validate course ID
            if (!validCourseIds.contains(courseId)) {
              print('Invalid course ID: $courseId');
              invalidExams.add({...exam, 'error': 'Course does not exist'});
              continue;
            }

            // Validate session
            if (!['MORNING', 'AFTERNOON'].contains(session)) {
              print('Invalid session: $session');
              invalidExams.add({
                ...exam,
                'error': 'Invalid session (must be MORNING or AFTERNOON)'
              });
              continue;
            }

            // Validate time format
            final timeRegex =
                RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$');
            if (!timeRegex.hasMatch(time)) {
              print('Invalid time format: $time');
              invalidExams.add(
                  {...exam, 'error': 'Invalid time format (must be HH:MM:SS)'});
              continue;
            }

            // Validate duration
            if (duration <= 0 || duration > 240) {
              print('Invalid duration: $duration');
              invalidExams.add({
                ...exam,
                'error': 'Invalid duration (must be between 1 and 240 minutes)'
              });
              continue;
            }

            validExams.add(exam);
            print('Added exam: $examId');
          } catch (e, stack) {
            print('Error processing row: $e');
            print('Stack trace: $stack');
          }
        }

        if (validExams.isEmpty && invalidExams.isEmpty) {
          throw Exception('No exams found in Excel file');
        }

        print(
            'Successfully parsed ${validExams.length} valid exams and found ${invalidExams.length} invalid exams');

        // Show preview dialog
        if (mounted) {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Preview Imported Exams'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (validExams.isNotEmpty) ...[
                        Text(
                            'Found ${validExams.length} valid exams to import:',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        ...validExams.map((exam) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.check_circle,
                                    color: Colors.green),
                                title: Text(exam['course_id']),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Date: ${DateFormat('MMM d, y').format(DateTime.parse(exam['exam_date']))}'),
                                    Text(
                                        'Session: ${exam['session']}, Time: ${exam['time']}'),
                                    Text('Duration: ${exam['duration']} mins'),
                                  ],
                                ),
                              ),
                            )),
                      ],
                      if (invalidExams.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('Found ${invalidExams.length} invalid exams:',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                        const SizedBox(height: 16),
                        ...invalidExams.map((exam) => Card(
                              color: Colors.red.shade50,
                              child: ListTile(
                                leading:
                                    const Icon(Icons.error, color: Colors.red),
                                title: Text(exam['course_id']),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Date: ${DateFormat('MMM d, y').format(DateTime.parse(exam['exam_date']))}'),
                                    Text(
                                        'Session: ${exam['session']}, Time: ${exam['time']}'),
                                    Text('Duration: ${exam['duration']} mins'),
                                    const SizedBox(height: 4),
                                    Text('Error: ${exam['error']}',
                                        style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 16),
                        const Text(
                            'Please fix these issues in the Excel file and try again.',
                            style: TextStyle(fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: invalidExams.isEmpty && validExams.isNotEmpty
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: Text(invalidExams.isEmpty
                      ? 'Import ${validExams.length} Exams'
                      : 'Fix Errors to Import'),
                ),
              ],
            ),
          );

          if (result == true && mounted) {
            print('Importing exams to database...');
            final repository = ref.read(examRepositoryProvider);
            await repository.scheduleExams(
              validExams.map((e) => Exam.fromJson(e)).toList(),
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Exams imported successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              ref.refresh(examsProvider);
            }
          }
        }
      } catch (e, stack) {
        print('Error decoding Excel: $e');
        print('Stack trace: $stack');
        throw Exception('Failed to decode Excel file: $e');
      }
    } catch (e, stack) {
      print('Error importing from Excel: $e');
      print('Stack trace: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing from Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _generateExamId(String courseId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch % 100;
    final id = 'EX$courseId${timestamp.toString().padLeft(2, '0')}';
    print('Generated exam ID: $id (length: ${id.length})');
    return id;
  }
}

class _PostponeExamDialog extends ConsumerStatefulWidget {
  final String examId;
  final DateTime currentDate;

  const _PostponeExamDialog({
    required this.examId,
    required this.currentDate,
  });

  @override
  _PostponeExamDialogState createState() => _PostponeExamDialogState();
}

class _PostponeExamDialogState extends ConsumerState<_PostponeExamDialog> {
  DateTime? _selectedDate;
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  bool get _canConfirm =>
      _selectedDate != null && _reasonController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.currentDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Postpone Exam'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(_selectedDate == null
                ? 'Select new date'
                : DateFormat('MMM d, y').format(_selectedDate!)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () => _selectDate(context),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason for postponement',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: (_) => setState(() {}), // Rebuild to update button state
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading || !_canConfirm
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  try {
                    await ref.read(examRepositoryProvider).postponeExam(
                          widget.examId,
                          _selectedDate!,
                          _reasonController.text.trim(),
                        );
                    if (mounted) {
                      Navigator.of(context).pop(true);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to postpone exam: $e')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                },
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm'),
        ),
      ],
    );
  }
}

class _AnimatedTodayBadge extends StatefulWidget {
  const _AnimatedTodayBadge();

  @override
  State<_AnimatedTodayBadge> createState() => _AnimatedTodayBadgeState();
}

class _AnimatedTodayBadgeState extends State<_AnimatedTodayBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(_animation.value),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 16,
            ),
            SizedBox(width: 4),
            Text(
              'Today',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildStatusBadge(DateTime examDate) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final examDay = DateTime(examDate.year, examDate.month, examDate.day);

  if (examDay.isBefore(today)) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Text(
        'Past',
        style: TextStyle(
          color: Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  } else if (examDay.isAfter(today)) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Text(
        'Upcoming',
        style: TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  } else {
    return const _AnimatedTodayBadge();
  }
}
