import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/presentation/providers/holiday_provider.dart';

class ExcelImportPreviewDialog extends ConsumerWidget {
  final List<Exam> exams;
  final List<String> existingCourses;

  const ExcelImportPreviewDialog({
    super.key,
    required this.exams,
    required this.existingCourses,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group exams by date
    final examsByDate = <DateTime, List<Exam>>{};
    for (var exam in exams) {
      final date = DateTime(
        exam.examDate.year,
        exam.examDate.month,
        exam.examDate.day,
      );
      examsByDate.putIfAbsent(date, () => []).add(exam);
    }

    // Sort dates
    final sortedDates = examsByDate.keys.toList()..sort();

    final holidaysAsync =
        ref.watch(holidaysProvider(exams.first.examDate.year));

    return holidaysAsync.when(
      data: (holidays) {
        return AlertDialog(
          title: const Text('Import Preview'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Exams: ${exams.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (existingCourses.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Warning: ${existingCourses.length} courses already have exams scheduled',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            existingCourses.join(', '),
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Exams by date
                  ...sortedDates.map((date) {
                    final dateExams = examsByDate[date]!;
                    final isSunday = date.weekday == DateTime.sunday;
                    final holiday = holidays
                        .where((h) =>
                            h.date.year == date.year &&
                            h.date.month == date.month &&
                            h.date.day == date.day)
                        .firstOrNull;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            DateFormat('EEEE, MMM d, y').format(date),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isSunday)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                    'Warning: Exams scheduled on Sunday'),
                              ],
                            ),
                          ),
                        if (holiday != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.celebration,
                                    color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                        ...dateExams.map((exam) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Text(exam.courseId),
                                    if (existingCourses
                                        .contains(exam.courseId)) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.red.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          'Already Scheduled',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade900,
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
                            )),
                        const Divider(),
                      ],
                    );
                  }),
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
              onPressed: existingCourses.isEmpty
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
