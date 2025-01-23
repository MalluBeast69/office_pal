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

  Course _getCourse(String courseId) {
    return courses.firstWhere((c) => c.courseCode == courseId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preview Exam Schedule'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                            Text(course.courseCode),
                            Text(
                              course.courseName,
                              style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check),
          label: const Text('Confirm Schedule'),
        ),
      ],
    );
  }
}
