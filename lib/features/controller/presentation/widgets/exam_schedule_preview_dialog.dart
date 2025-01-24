import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamSchedulePreviewDialog extends StatelessWidget {
  final List<Exam> exams;
  final DateTime selectedDate;

  const ExamSchedulePreviewDialog({
    super.key,
    required this.exams,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    print('Building ExamSchedulePreviewDialog');
    print('Selected date: $selectedDate');
    print('Number of exams: ${exams.length}');
    for (var exam in exams) {
      print('Exam: ${exam.toString()}');
    }

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Preview for ${DateFormat('MMM d, y').format(selectedDate)}'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              print('Preview dialog: Close button pressed');
              Navigator.of(context).pop(false);
            },
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: exams.isEmpty
            ? const Center(
                child: Text('No exams scheduled for this date'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: exams.length,
                itemBuilder: (context, index) {
                  final exam = exams[index];
                  return Card(
                    child: ListTile(
                      title: Text(exam.courseId),
                      subtitle: Text(
                          '${exam.session} - ${exam.time} (${exam.duration} mins)'),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            print('Preview dialog: Cancel button pressed');
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            print('Preview dialog: Confirm button pressed');
            Navigator.of(context).pop(true);
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
