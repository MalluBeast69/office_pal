import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/data/repositories/exam_repository.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';

class ExamHistoryDialog extends ConsumerStatefulWidget {
  const ExamHistoryDialog({super.key});

  @override
  ConsumerState<ExamHistoryDialog> createState() => _ExamHistoryDialogState();
}

class _ExamHistoryDialogState extends ConsumerState<ExamHistoryDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _examHistory = [];

  @override
  void initState() {
    super.initState();
    _loadExamHistory();
  }

  Future<void> _loadExamHistory() async {
    try {
      setState(() => _isLoading = true);
      final repository = ref.read(examRepositoryProvider);
      final history = await repository.getExamHistory();
      if (mounted) {
        setState(() {
          _examHistory = history;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading exam history: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteExam(String id, String courseCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content:
            Text('Are you sure you want to delete the exam for $courseCode?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final repository = ref.read(examRepositoryProvider);
        await repository.deleteExamHistory(id);
        await _loadExamHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting exam: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exam History'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _examHistory.isEmpty
                ? const Center(
                    child: Text('No exam history found'),
                  )
                : SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Course')),
                        DataColumn(label: Text('Time')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _examHistory.map((exam) {
                        final course = exam['course'] as Map<String, dynamic>;
                        return DataRow(
                          cells: [
                            DataCell(Text(
                              DateFormat('MMM d, y').format(
                                DateTime.parse(exam['exam_date'] as String),
                              ),
                            )),
                            DataCell(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(course['course_code'] as String),
                                Text(
                                  course['course_name'] as String,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            )),
                            DataCell(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(exam['time'] as String),
                                Text(
                                  exam['session'] as String,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            )),
                            DataCell(IconButton(
                              icon: const Icon(Icons.delete),
                              color: Colors.red,
                              onPressed: () => _deleteExam(
                                exam['id'] as String,
                                course['course_code'] as String,
                              ),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
