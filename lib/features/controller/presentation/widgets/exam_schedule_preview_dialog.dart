import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/presentation/providers/holiday_provider.dart';

class ExamSchedulePreviewDialog extends ConsumerWidget {
  final List<Exam> exams;
  final DateTime selectedDate;

  const ExamSchedulePreviewDialog({
    super.key,
    required this.exams,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('Building ExamSchedulePreviewDialog');
    print('Selected date: $selectedDate');
    print('Number of exams: ${exams.length}');
    for (var exam in exams) {
      print('Exam: ${exam.toString()}');
    }

    final bool isSunday = selectedDate.weekday == DateTime.sunday;
    final holidaysAsync = ref.watch(holidaysProvider(selectedDate.year));

    return holidaysAsync.when(
      data: (holidays) {
        final holiday = holidays
            .where((h) =>
                h.date.year == selectedDate.year &&
                h.date.month == selectedDate.month &&
                h.date.day == selectedDate.day)
            .firstOrNull;

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  'Preview for ${DateFormat('MMM d, y').format(selectedDate)}'),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSunday)
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    margin: const EdgeInsets.only(bottom: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade700),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            'Warning: Exams are scheduled for a Sunday',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (holiday != null)
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.celebration, color: Colors.red.shade700),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Warning: Holiday on this date',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${holiday.name} (${holiday.type})',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Flexible(
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
                              color: isSunday ? Colors.orange.shade50 : null,
                              child: ListTile(
                                leading: isSunday
                                    ? Tooltip(
                                        message: 'Scheduled on Sunday',
                                        child: Icon(
                                          Icons.calendar_today,
                                          color: Colors.orange.shade700,
                                        ),
                                      )
                                    : null,
                                title: Row(
                                  children: [
                                    Text(exam.courseId),
                                    if (isSunday) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.orange.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          'Sunday',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '${exam.session} - ${exam.time} (${exam.duration} mins)',
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
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
      },
      error: (e, _) => Center(child: Text('Error: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
