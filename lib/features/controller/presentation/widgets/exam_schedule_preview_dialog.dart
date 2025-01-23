import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamSchedulePreviewDialog extends StatelessWidget {
  final List<Exam> exams;
  final List<Course> courses;

  const ExamSchedulePreviewDialog({
    super.key,
    required this.exams,
    required this.courses,
  });

  Course? _getCourse(String courseId) {
    try {
      return courses.firstWhere((c) => c.courseCode == courseId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasErrors = exams.any((exam) => _getCourse(exam.courseId) == null);

    return AlertDialog(
      title: const Text('Preview Exam Schedule'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasErrors)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Some courses were not found in the database. Please check the course codes.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Course')),
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('Duration')),
                  ],
                  rows: exams.map((exam) {
                    final course = _getCourse(exam.courseId);
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          DateFormat('MMM d, y').format(exam.examDate),
                        )),
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(exam.courseId),
                            if (course != null)
                              Text(
                                course.courseName,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              Text(
                                '(Course not found)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.red),
                              ),
                          ],
                        )),
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(exam.time),
                            Text(
                              exam.session,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        )),
                        DataCell(Text('${exam.duration} mins')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: hasErrors ? null : () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check),
          label: const Text('Confirm Schedule'),
        ),
      ],
    );
  }
}
