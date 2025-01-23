import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/presentation/widgets/exam_schedule_preview_dialog.dart';
import 'package:office_pal/features/controller/presentation/widgets/pdf_preview_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:office_pal/features/controller/utils/exam_timetable_excel.dart';

enum ExamSession { morning, afternoon }

class ExamSchedulingDialog extends ConsumerStatefulWidget {
  final List<Course> selectedCourses;

  const ExamSchedulingDialog({
    super.key,
    required this.selectedCourses,
  });

  @override
  ConsumerState<ExamSchedulingDialog> createState() =>
      _ExamSchedulingDialogState();
}

class _ExamSchedulingDialogState extends ConsumerState<ExamSchedulingDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;
  ExamSession _selectedSession = ExamSession.morning;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final _durationController = TextEditingController(text: '180');

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  String _generateExamId(String courseId) {
    return 'EX$courseId${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  Future<void> _scheduleExams() async {
    if (!_formKey.currentState!.validate()) return;

    final exams = widget.selectedCourses.map((course) {
      return Exam(
        examId: _generateExamId(course.courseCode),
        courseId: course.courseCode,
        examDate: _selectedDate!,
        session: _selectedSession.name.toUpperCase(),
        time:
            '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00',
        duration: course.examDuration,
      );
    }).toList();

    // Show preview dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ExamSchedulePreviewDialog(
        exams: exams,
        courses: widget.selectedCourses,
      ),
    );

    if (result == true && mounted) {
      try {
        final repository = ref.read(examRepositoryProvider);
        await repository.scheduleExams(exams);

        // Generate and show Excel
        await _generateAndShowExcel(exams, widget.selectedCourses);

        if (mounted) {
          Navigator.of(context).pop(exams);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error scheduling exams: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _generateAndShowExcel(
      List<Exam> exams, List<Course> courses) async {
    try {
      final excelBytes = ExamTimetableExcel.generate(exams, courses);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => ExcelPreviewDialog(
            excelBytes: excelBytes,
            fileName:
                'exam_timetable_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.xlsx',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importFromCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (result != null) {
        final bytes = result.files.first.bytes!;
        final excel = Excel.decodeBytes(bytes);
        final sheet = excel.tables[excel.tables.keys.first]!;

        List<Exam> importedExams = [];

        // Skip header row
        for (var row in sheet.rows.skip(1)) {
          if (row[0]?.value == null) continue;

          try {
            final courseId = row[0]!.value.toString();
            final date = DateTime.parse(row[1]!.value.toString());
            final session = row[2]!.value.toString().toUpperCase();
            final time = row[3]!.value.toString();
            final duration = int.parse(row[4]!.value.toString());

            importedExams.add(Exam(
              examId: _generateExamId(courseId),
              courseId: courseId,
              examDate: date,
              session: session,
              time: time,
              duration: duration,
            ));
          } catch (e) {
            print('Error parsing row: $e');
            continue;
          }
        }

        if (importedExams.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No valid exams found in the file'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Show preview dialog
        final previewResult = await showDialog<bool>(
          context: context,
          builder: (context) => ExamSchedulePreviewDialog(
            exams: importedExams,
            courses: widget.selectedCourses,
          ),
        );

        if (previewResult == true && mounted) {
          try {
            final repository = ref.read(examRepositoryProvider);
            await repository.scheduleExams(importedExams);

            // Generate and show Excel
            await _generateAndShowExcel(importedExams, widget.selectedCourses);

            if (mounted) {
              Navigator.of(context).pop(importedExams);
            }
          } catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error scheduling exams: $error'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing file: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Schedule Exams'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _importFromCSV,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import from CSV'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Selected Courses (${widget.selectedCourses.length}):'),
              const SizedBox(height: 8),
              ...widget.selectedCourses.map((course) => Text(
                    '• ${course.courseCode} - ${course.courseName} (${course.examDuration} mins)',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
              const SizedBox(height: 24),
              // Date Selection
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exam Date'),
                subtitle: Text(
                  _selectedDate == null
                      ? 'Select a date'
                      : DateFormat('EEEE, MMMM d, y').format(_selectedDate!),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _selectDate,
                ),
              ),
              const SizedBox(height: 16),
              // Session Selection
              const Text('Session'),
              const SizedBox(height: 8),
              SegmentedButton<ExamSession>(
                segments: const [
                  ButtonSegment(
                    value: ExamSession.morning,
                    label: Text('Morning'),
                  ),
                  ButtonSegment(
                    value: ExamSession.afternoon,
                    label: Text('Afternoon'),
                  ),
                ],
                selected: {_selectedSession},
                onSelectionChanged: (Set<ExamSession> selected) {
                  setState(() {
                    _selectedSession = selected.first;
                    _selectedTime = TimeOfDay(
                      hour: _selectedSession == ExamSession.morning ? 9 : 14,
                      minute: 0,
                    );
                  });
                },
              ),
              const SizedBox(height: 16),
              // Time Selection
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start Time'),
                subtitle: Text(_selectedTime.format(context)),
                trailing: IconButton(
                  icon: const Icon(Icons.access_time),
                  onPressed: _selectTime,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedDate == null ? null : _scheduleExams,
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}
