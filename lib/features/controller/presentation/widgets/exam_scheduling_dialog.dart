import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/presentation/widgets/exam_schedule_preview_dialog.dart';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:office_pal/features/controller/utils/exam_timetable_excel.dart';
import 'package:office_pal/features/controller/presentation/widgets/excel_preview_dialog.dart';

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
    // Format: EX + courseId + 2 digits (total 11 chars)
    // Example: EXDPME10492 (EX + DPME104 + 92)
    final timestamp = DateTime.now().millisecondsSinceEpoch % 100;
    final id = 'EX$courseId${timestamp.toString().padLeft(2, '0')}';
    print('Generated exam ID: $id (length: ${id.length})');
    if (id.length != 11) {
      print('WARNING: Generated ID length is not 11 characters!');
    }
    return id;
  }

  Future<void> _scheduleExams() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final repository = ref.read(examRepositoryProvider);
      final courseIds =
          widget.selectedCourses.map((c) => c.courseCode).toList();

      // Check for existing exams
      final existingExams = await repository.getExams();
      final conflictingCourses = existingExams
          .where((e) => courseIds.contains(e['course_id']))
          .map((e) => Exam(
                examId: e['exam_id'],
                courseId: e['course_id'],
                examDate: DateTime.parse(e['exam_date']),
                session: e['session'],
                time: e['time'],
                duration: e['duration'],
              ))
          .toList();

      if (conflictingCourses.isNotEmpty) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (context) => ExamSchedulePreviewDialog(
            exams: conflictingCourses,
            selectedDate: _selectedDate!,
          ),
        );
        return;
      }

      // Create new exams
      final exams = widget.selectedCourses.map((course) {
        final examId = _generateExamId(course.courseCode);
        final time =
            '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';
        final examDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

        return Exam(
          examId: examId,
          courseId: course.courseCode,
          examDate: _selectedDate!,
          session: _selectedSession.name.toUpperCase(),
          time: time,
          duration: course.examDuration,
        );
      }).toList();

      // Show preview
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => ExamSchedulePreviewDialog(
          exams: exams,
          selectedDate: _selectedDate!,
        ),
      );

      if (result == true && mounted) {
        await repository.scheduleExams(exams);

        // Show success dialog with Excel download option
        if (mounted) {
          final downloadExcel = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Exams Scheduled Successfully'),
              content: const Text(
                  'Would you like to download the schedule as Excel?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Download Excel'),
                ),
              ],
            ),
          );

          if (downloadExcel == true) {
            await _generateExcel();
          }
        }

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

  Future<void> _generateExcel() async {
    try {
      final repository = ref.read(examRepositoryProvider);
      final exams = await repository.generateExcelData();

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => ExcelPreviewDialog(
          excelBytes: ExamTimetableExcel.generate(
            exams.map((e) => Exam.fromJson(e)).toList(),
            widget.selectedCourses,
          ),
          fileName:
              'exam_schedule_${DateFormat('yyyyMMdd').format(_selectedDate!)}.xlsx',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $e'),
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
            children: [
              ListTile(
                title: Text(_selectedDate == null
                    ? 'Select Date'
                    : DateFormat('MMM d, y').format(_selectedDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
              ),
              const Divider(),
              ListTile(
                title: const Text('Session'),
                trailing: DropdownButton<ExamSession>(
                  value: _selectedSession,
                  items: ExamSession.values.map((session) {
                    return DropdownMenuItem(
                      value: session,
                      child: Text(session.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSession = value);
                    }
                  },
                ),
              ),
              const Divider(),
              ListTile(
                title: Text('Time: ${_selectedTime.format(context)}'),
                trailing: const Icon(Icons.access_time),
                onTap: _selectTime,
              ),
              const Divider(),
              const Text('Selected Courses:'),
              ...widget.selectedCourses.map((course) => ListTile(
                    title: Text(course.courseCode),
                    subtitle: Text('Duration: ${course.examDuration} minutes'),
                  )),
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
          onPressed: _scheduleExams,
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}
