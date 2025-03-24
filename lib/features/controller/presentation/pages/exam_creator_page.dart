import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/data/repositories/exam_repository.dart';
import 'package:office_pal/features/controller/presentation/providers/course_provider.dart';

final examRepositoryProvider =
    Provider<ExamRepository>((ref) => ExamRepository());

final examRowsProvider =
    StateNotifierProvider<ExamRowsNotifier, List<ExamRow>>((ref) {
  return ExamRowsNotifier();
});

class ExamRow {
  final String examId;
  String courseId;
  DateTime examDate;
  String time;
  String session;
  int duration;
  bool isValid;
  Map<String, String> errors;
  bool isSelected;

  ExamRow({
    required this.examId,
    required this.courseId,
    required this.examDate,
    required this.time,
    required this.session,
    required this.duration,
    this.isValid = true,
    this.errors = const {},
    this.isSelected = false,
  });

  ExamRow copyWith({
    String? examId,
    String? courseId,
    DateTime? examDate,
    String? time,
    String? session,
    int? duration,
    bool? isValid,
    Map<String, String>? errors,
    bool? isSelected,
  }) {
    return ExamRow(
      examId: examId ?? this.examId,
      courseId: courseId ?? this.courseId,
      examDate: examDate ?? this.examDate,
      time: time ?? this.time,
      session: session ?? this.session,
      duration: duration ?? this.duration,
      isValid: isValid ?? this.isValid,
      errors: errors ?? this.errors,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class ExamRowsNotifier extends StateNotifier<List<ExamRow>> {
  ExamRowsNotifier() : super([]);

  String _generateUniqueExamId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (1000 + (timestamp % 1000)).toString().padLeft(4, '0');
    final year = DateTime.now().year.toString().substring(2);
    final month = DateTime.now().month.toString().padLeft(2, '0');
    final examId = 'EX$year$month$random';

    print('DEBUG: Generating examId: $examId');

    // Check if ID already exists in current rows
    final isDuplicate = state.any((row) => row.examId == examId);
    if (isDuplicate) {
      print('DEBUG: Duplicate examId found: $examId, generating new one');
      // If duplicate, recursively try again
      return _generateUniqueExamId();
    }

    print('DEBUG: Generated unique examId: $examId');
    return examId;
  }

  // Public method to generate unique exam ID
  String generateExamId() {
    return _generateUniqueExamId();
  }

  void addRow() {
    final uniqueExamId = generateExamId();
    print('DEBUG: Adding new row with generated examId: $uniqueExamId');

    state = [
      ...state,
      ExamRow(
        examId: uniqueExamId,
        courseId: '',
        examDate: DateTime.now(),
        time: '09:00',
        session: 'MORNING',
        duration: 180,
        isSelected: false,
      ),
    ];

    print('DEBUG: Row added successfully with examId: $uniqueExamId');
  }

  void updateRow(int index, ExamRow row) {
    state = [
      ...state.sublist(0, index),
      row,
      ...state.sublist(index + 1),
    ];
  }

  void removeRow(int index) {
    state = [
      ...state.sublist(0, index),
      ...state.sublist(index + 1),
    ];
  }

  void duplicateRow(int index) {
    final row = state[index];
    final uniqueExamId = generateExamId();
    print('DEBUG: Duplicating row index $index with new examId: $uniqueExamId');

    state = [
      ...state,
      row.copyWith(
        examId: uniqueExamId,
        isSelected: false,
      ),
    ];

    print('DEBUG: Row duplicated successfully with new examId: $uniqueExamId');
  }

  void deleteAll() {
    state = [];
  }

  void setAllSelected(bool selected) {
    state = state.map((row) => row.copyWith(isSelected: selected)).toList();
  }

  void deleteSelected() {
    state = state.where((row) => !row.isSelected).toList();
  }
}

class ExamCreatorPage extends ConsumerStatefulWidget {
  const ExamCreatorPage({super.key});

  @override
  ConsumerState<ExamCreatorPage> createState() => _ExamCreatorPageState();
}

class _ExamCreatorPageState extends ConsumerState<ExamCreatorPage> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  bool _showOnlyProblematicRows = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _showCourseSelectionDialog(
      int rowIndex, ExamRow currentRow) async {
    final coursesAsync = ref.read(coursesProvider);
    final allRows = ref.read(examRowsProvider);
    final existingCourses = allRows
        .where((row) => row.courseId.isNotEmpty)
        .map((row) => row.courseId)
        .toList();

    return showDialog(
      context: context,
      builder: (context) => CourseSelectionDialog(
        coursesAsync: coursesAsync,
        currentCourseId: currentRow.courseId,
        existingCourses: existingCourses,
        onCoursesSelected: (selectedCourses) {
          // Create new rows for each selected course
          for (var i = 0; i < selectedCourses.length; i++) {
            final courseId = selectedCourses[i];
            if (i == 0) {
              // Update the current row
              ref.read(examRowsProvider.notifier).updateRow(
                    rowIndex,
                    currentRow.copyWith(courseId: courseId),
                  );
            } else {
              // Add new rows for additional courses
              print('DEBUG: Adding new row for course: $courseId');
              final uniqueExamId =
                  ref.read(examRowsProvider.notifier).generateExamId();
              print('DEBUG: Generated unique exam ID: $uniqueExamId');

              ref.read(examRowsProvider.notifier).addRow();
              final newRowIndex = ref.read(examRowsProvider).length - 1;
              ref.read(examRowsProvider.notifier).updateRow(
                    newRowIndex,
                    ExamRow(
                      examId: uniqueExamId,
                      courseId: courseId,
                      examDate: currentRow.examDate,
                      time: currentRow.time,
                      session: currentRow.session,
                      duration: currentRow.duration,
                    ),
                  );
              print(
                  'DEBUG: Added new row with examId: $uniqueExamId and courseId: $courseId');
            }
          }
        },
      ),
    );
  }

  Future<void> _submitExams() async {
    final rows = ref.read(examRowsProvider);

    // Validate all rows
    bool hasErrors = false;
    List<String> errorMessages = [];

    // First check for duplicate exam IDs
    final examIds = <String>{};
    final duplicateExamIds = <String>{};

    for (var row in rows) {
      if (examIds.contains(row.examId)) {
        duplicateExamIds.add(row.examId);
      } else {
        examIds.add(row.examId);
      }
    }

    if (duplicateExamIds.isNotEmpty) {
      hasErrors = true;
      errorMessages
          .add('Duplicate exam IDs found: ${duplicateExamIds.join(', ')}');
      print('DEBUG: Found duplicate exam IDs: ${duplicateExamIds.join(', ')}');
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final errors = <String, String>{};
      final rowErrors = <String>[];

      // Check for duplicate exam ID
      if (duplicateExamIds.contains(row.examId)) {
        errors['examId'] = 'Duplicate exam ID';
        rowErrors.add('Duplicate exam ID: ${row.examId}');
      }

      // Required field validations
      if (row.courseId.isEmpty) {
        errors['courseId'] = 'Course is required';
        rowErrors.add('Course is required');
      }

      if (row.examDate.isBefore(DateTime.now())) {
        errors['examDate'] = 'Exam date cannot be in the past';
        rowErrors.add('Exam date cannot be in the past');
      }

      if (row.session.isEmpty) {
        errors['session'] = 'Session is required';
        rowErrors.add('Session is required');
      }

      if (row.time.isEmpty) {
        errors['time'] = 'Time is required';
        rowErrors.add('Time is required');
      }

      // Duration validation (must be > 0 per DB constraint)
      if (row.duration <= 0) {
        errors['duration'] = 'Duration must be greater than 0';
        rowErrors.add('Duration must be greater than 0');
      }

      // Time validation based on session
      final timeComponents = row.time.split(':');
      final hour = int.parse(timeComponents[0]);

      if (row.session == 'MORNING' && hour >= 12) {
        errors['time'] = 'Morning session must be before 12:00 PM';
        rowErrors.add('Morning session must be before 12:00 PM');
      } else if (row.session == 'AFTERNOON' && (hour < 12 || hour >= 18)) {
        errors['time'] =
            'Afternoon session must be between 12:00 PM and 6:00 PM';
        rowErrors.add('Afternoon session must be between 12:00 PM and 6:00 PM');
      }

      // Check for duplicate course IDs
      if (row.courseId.isNotEmpty) {
        final duplicateCourse = rows.indexWhere(
            (otherRow) => otherRow.courseId == row.courseId && otherRow != row);
        if (duplicateCourse != -1) {
          errors['courseId'] =
              'This course is already scheduled in row ${duplicateCourse + 1}';
          rowErrors.add(
              'Course ${row.courseId} is already scheduled in row ${duplicateCourse + 1}');
        }
      }

      // Update row with any errors
      if (errors.isNotEmpty) {
        hasErrors = true;
        errorMessages.add(
            'Row ${i + 1} (${row.examId}) has the following errors:\n${rowErrors.map((e) => "  - $e").join("\n")}');
        ref.read(examRowsProvider.notifier).updateRow(
              i,
              row.copyWith(isValid: false, errors: errors),
            );
      } else {
        ref.read(examRowsProvider.notifier).updateRow(
              i,
              row.copyWith(isValid: true, errors: const {}),
            );
      }
    }

    if (hasErrors) {
      if (mounted) {
        // Show detailed error dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Validation Errors'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The following errors were found:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...errorMessages.map((error) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(error),
                      )),
                  const SizedBox(height: 16),
                  const Text(
                    'Please fix these errors before submitting.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _showOnlyProblematicRows = true);
                },
                icon: const Icon(Icons.filter_list),
                label: const Text('Show Problem Rows'),
              ),
            ],
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fix the errors in the highlighted rows'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Convert rows to Exam objects and submit
      final exams = rows
          .map((row) => Exam(
                examId: row.examId,
                courseId: row.courseId,
                examDate: row.examDate,
                session: row.session,
                time: row.time,
                duration: row.duration,
              ))
          .toList();

      // Submit exams to the database
      final repository = ref.read(examRepositoryProvider);
      await repository.scheduleExams(exams);

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully created ${exams.length} exams'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Navigate back
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show detailed error dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Error Creating Exams'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'An error occurred while creating the exams:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(e.toString()),
                  const SizedBox(height: 16),
                  const Text(
                    'If this error persists, please contact support.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(examRowsProvider);
    final selectedCount = rows.where((row) => row.isSelected).length;
    final hasProblematicRows = rows.any((row) => !row.isValid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Exams'),
        actions: [
          if (hasProblematicRows) ...[
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showOnlyProblematicRows = !_showOnlyProblematicRows;
                });
              },
              icon: Icon(_showOnlyProblematicRows
                  ? Icons.filter_list_off
                  : Icons.filter_list),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _showOnlyProblematicRows ? Colors.orange : Colors.blue,
              ),
              label:
                  Text(_showOnlyProblematicRows ? 'Show All' : 'Show Errors'),
            ),
            const SizedBox(width: 16),
          ],
          if (selectedCount > 0) ...[
            Text(
              '$selectedCount selected',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Selected Rows'),
                    content: Text(
                        'Are you sure you want to delete $selectedCount selected rows?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          ref.read(examRowsProvider.notifier).deleteSelected();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              label: const Text('Delete Selected'),
            ),
            const SizedBox(width: 16),
          ] else ...[
            FilledButton.icon(
              onPressed: _submitExams,
              icon: const Icon(Icons.save),
              label: const Text('Submit Exams'),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: Column(
        children: [
          if (hasProblematicRows && !_showOnlyProblematicRows)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'There are errors in some rows. Click "Show Errors" to view only problematic rows.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showOnlyProblematicRows = true;
                      });
                    },
                    child: const Text('Show Errors'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _verticalScrollController,
              thumbVisibility: true,
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.depth == 1,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      columns: [
                        const DataColumn(label: Text('Exam ID')),
                        DataColumn(
                          label: Row(
                            children: [
                              const Text('Course'),
                              if (hasProblematicRows)
                                const Tooltip(
                                  message:
                                      'Some courses have validation errors',
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const DataColumn(label: Text('Date')),
                        const DataColumn(label: Text('Session')),
                        const DataColumn(label: Text('Time')),
                        const DataColumn(label: Text('Duration (mins)')),
                        const DataColumn(label: Text('Actions')),
                      ],
                      rows: List.generate(rows.length, (index) {
                        final row = rows[index];
                        if (_showOnlyProblematicRows && row.isValid) {
                          return null;
                        }
                        return DataRow(
                          selected: row.isSelected,
                          color: WidgetStateProperty.resolveWith((states) {
                            if (!row.isValid) return Colors.red.shade50;
                            if (states.contains(WidgetState.selected)) {
                              return Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withOpacity(0.12);
                            }
                            return null;
                          }),
                          cells: [
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: row.isSelected,
                                    onChanged: (bool? value) {
                                      ref
                                          .read(examRowsProvider.notifier)
                                          .updateRow(
                                            index,
                                            row.copyWith(isSelected: value),
                                          );
                                    },
                                  ),
                                  Text(row.examId),
                                ],
                              ),
                            ),
                            DataCell(
                              InkWell(
                                onTap: () =>
                                    _showCourseSelectionDialog(index, row),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: row.errors['courseId'] != null
                                          ? Colors.red
                                          : Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(row.courseId.isEmpty
                                          ? 'Select Course'
                                          : row.courseId),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.search, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: row.examDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                  );
                                  if (date != null) {
                                    ref
                                        .read(examRowsProvider.notifier)
                                        .updateRow(
                                          index,
                                          row.copyWith(examDate: date),
                                        );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: row.errors['examDate'] != null
                                          ? Colors.red
                                          : Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(DateFormat('MMM d, y')
                                      .format(row.examDate)),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButton<String>(
                                  value: row.session,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'MORNING',
                                      child: Text('MORNING'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AFTERNOON',
                                      child: Text('AFTERNOON'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      // Reset time based on session
                                      final defaultTime = value == 'MORNING'
                                          ? '09:00'
                                          : '14:00';
                                      ref
                                          .read(examRowsProvider.notifier)
                                          .updateRow(
                                            index,
                                            row.copyWith(
                                              session: value,
                                              time: defaultTime,
                                            ),
                                          );
                                    }
                                  },
                                ),
                              ),
                            ),
                            DataCell(
                              InkWell(
                                onTap: row.session.isEmpty
                                    ? null
                                    : () async {
                                        final time = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(
                                            DateFormat('HH:mm').parse(row.time),
                                          ),
                                          builder: (context, child) {
                                            return MediaQuery(
                                              data: MediaQuery.of(context)
                                                  .copyWith(
                                                alwaysUse24HourFormat: false,
                                              ),
                                              child: child!,
                                            );
                                          },
                                        );
                                        if (time != null) {
                                          final hour = time.hour;
                                          final isValidTime =
                                              row.session == 'MORNING'
                                                  ? hour < 12
                                                  : hour >= 12 && hour < 18;

                                          if (!isValidTime) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(row.session ==
                                                          'MORNING'
                                                      ? 'Morning session must be before 12:00 PM'
                                                      : 'Afternoon session must be between 12:00 PM and 6:00 PM'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                            return;
                                          }

                                          // Store in 24h format but display in 12h
                                          final timeStr =
                                              '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                          ref
                                              .read(examRowsProvider.notifier)
                                              .updateRow(
                                                index,
                                                row.copyWith(time: timeStr),
                                              );
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    color: row.session.isEmpty
                                        ? Colors.grey.shade100
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        // Convert 24h to 12h format for display
                                        DateFormat('hh:mm a').format(
                                          DateTime.parse(
                                              '2024-01-01 ${row.time}:00'),
                                        ),
                                        style: TextStyle(
                                          color: row.session.isEmpty
                                              ? Colors.grey
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: row.session.isEmpty
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: row.errors['duration'] != null
                                        ? Colors.red
                                        : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      iconSize: 20,
                                      onPressed: row.duration <= 30
                                          ? null
                                          : () {
                                              ref
                                                  .read(
                                                      examRowsProvider.notifier)
                                                  .updateRow(
                                                    index,
                                                    row.copyWith(
                                                        duration:
                                                            row.duration - 30),
                                                  );
                                            },
                                    ),
                                    Container(
                                      width: 50,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: TextFormField(
                                        initialValue: row.duration.toString(),
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 8,
                                          ),
                                        ),
                                        onChanged: (value) {
                                          final duration = int.tryParse(value);
                                          if (duration != null) {
                                            ref
                                                .read(examRowsProvider.notifier)
                                                .updateRow(
                                                  index,
                                                  row.copyWith(
                                                      duration: duration),
                                                );
                                          }
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      iconSize: 20,
                                      onPressed: row.duration >= 360
                                          ? null
                                          : () {
                                              ref
                                                  .read(
                                                      examRowsProvider.notifier)
                                                  .updateRow(
                                                    index,
                                                    row.copyWith(
                                                        duration:
                                                            row.duration + 30),
                                                  );
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      ref
                                          .read(examRowsProvider.notifier)
                                          .duplicateRow(index);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () {
                                      ref
                                          .read(examRowsProvider.notifier)
                                          .removeRow(index);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).whereType<DataRow>().toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: () {
                    ref.read(examRowsProvider.notifier).addRow();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Row'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete All Rows'),
                              content: Text(
                                  'Are you sure you want to delete all ${rows.length} rows?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton.icon(
                                  onPressed: () {
                                    ref
                                        .read(examRowsProvider.notifier)
                                        .deleteAll();
                                    Navigator.pop(context);
                                    // Add initial row after deleting all
                                    ref
                                        .read(examRowsProvider.notifier)
                                        .addRow();
                                  },
                                  icon: const Icon(Icons.delete),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  label: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );
                        },
                  icon: const Icon(Icons.delete_sweep),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  label: const Text('Delete All'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CourseSelectionDialog extends ConsumerStatefulWidget {
  final AsyncValue<List<Map<String, dynamic>>> coursesAsync;
  final String currentCourseId;
  final Function(List<String>) onCoursesSelected;
  final List<String> existingCourses;

  const CourseSelectionDialog({
    super.key,
    required this.coursesAsync,
    required this.currentCourseId,
    required this.onCoursesSelected,
    required this.existingCourses,
  });

  @override
  ConsumerState<CourseSelectionDialog> createState() =>
      _CourseSelectionDialogState();
}

class _CourseSelectionDialogState extends ConsumerState<CourseSelectionDialog> {
  String _searchQuery = '';
  String? _selectedSemester;
  String? _selectedDepartment;
  String? _selectedCourseType;
  final Set<String> _selectedCourses = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Courses',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedCourses.isEmpty
                        ? null
                        : () {
                            widget.onCoursesSelected(_selectedCourses.toList());
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.check),
                    label: Text('Select (${_selectedCourses.length})'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.existingCourses.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The following courses are already scheduled: ${widget.existingCourses.join(", ")}',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by course code or name',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedSemester,
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Semesters'),
                        ),
                        ...List.generate(8, (index) => index + 1)
                            .map((sem) => DropdownMenuItem(
                                  value: sem.toString(),
                                  child: Text('Semester $sem'),
                                )),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedSemester = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: widget.coursesAsync.when(
                      data: (courses) {
                        final departments = courses
                            .map((c) => c['dept_id'] as String)
                            .toSet()
                            .toList()
                          ..sort();
                        return DropdownButtonFormField<String>(
                          value: _selectedDepartment,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All Departments'),
                            ),
                            ...departments.map((dept) => DropdownMenuItem(
                                  value: dept,
                                  child: Text(dept),
                                )),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedDepartment = value),
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const Text('Error loading departments'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              widget.coursesAsync.when(
                data: (courses) {
                  final courseTypes = courses
                      .map((c) => c['course_type'] as String)
                      .toSet()
                      .toList()
                    ..sort();
                  return DropdownButtonFormField<String>(
                    value: _selectedCourseType,
                    decoration: const InputDecoration(
                      labelText: 'Course Type',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Types'),
                      ),
                      ...courseTypes.map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.toUpperCase()),
                          )),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedCourseType = value),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('Error loading course types'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: widget.coursesAsync.when(
                  data: (courses) {
                    final filteredCourses = courses.where((course) {
                      if (_searchQuery.isNotEmpty) {
                        final query = _searchQuery.toLowerCase();
                        final code =
                            course['course_code'].toString().toLowerCase();
                        final name =
                            course['course_name'].toString().toLowerCase();
                        if (!code.contains(query) && !name.contains(query)) {
                          return false;
                        }
                      }

                      if (_selectedSemester != null) {
                        final semester = course['semester'].toString();
                        if (semester != _selectedSemester) {
                          return false;
                        }
                      }

                      if (_selectedDepartment != null) {
                        final dept = course['dept_id'].toString();
                        if (dept != _selectedDepartment) {
                          return false;
                        }
                      }

                      if (_selectedCourseType != null) {
                        final type = course['course_type'].toString();
                        if (type != _selectedCourseType) {
                          return false;
                        }
                      }

                      return true;
                    }).toList();

                    final availableCourses = filteredCourses
                        .where((course) => !widget.existingCourses
                            .contains(course['course_code']))
                        .toList();

                    final allCurrentlySelected = availableCourses.isNotEmpty &&
                        availableCourses.every((course) =>
                            _selectedCourses.contains(course['course_code']));

                    return Column(
                      children: [
                        // Select All checkbox
                        if (availableCourses.isNotEmpty) ...[
                          ListTile(
                            leading: Checkbox(
                              value: allCurrentlySelected,
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedCourses.addAll(
                                      availableCourses.map(
                                          (c) => c['course_code'] as String),
                                    );
                                  } else {
                                    _selectedCourses.removeAll(
                                      availableCourses.map(
                                          (c) => c['course_code'] as String),
                                    );
                                  }
                                });
                              },
                            ),
                            title: Text(
                              'Select All Filtered Courses (${availableCourses.length})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Divider(),
                        ],
                        Expanded(
                          child: ListView.builder(
                            itemCount: filteredCourses.length,
                            itemBuilder: (context, index) {
                              final course = filteredCourses[index];
                              final courseCode =
                                  course['course_code'] as String;
                              final isAlreadyScheduled =
                                  widget.existingCourses.contains(courseCode) &&
                                      courseCode != widget.currentCourseId;

                              return ListTile(
                                leading: Checkbox(
                                  value: _selectedCourses.contains(courseCode),
                                  onChanged: isAlreadyScheduled
                                      ? null
                                      : (bool? value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedCourses.add(courseCode);
                                            } else {
                                              _selectedCourses
                                                  .remove(courseCode);
                                            }
                                          });
                                        },
                                ),
                                title: Text(
                                  '${course['course_code']} - ${course['course_name']}',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Semester ${course['semester']} | ${course['dept_id']} | ${course['course_type'].toString().toUpperCase()} | ${course['credit']} Credits',
                                    ),
                                    if (isAlreadyScheduled)
                                      Text(
                                        'Already scheduled in another row',
                                        style: TextStyle(
                                          color: Colors.orange.shade800,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                                enabled: !isAlreadyScheduled,
                                tileColor: isAlreadyScheduled
                                    ? Colors.orange.shade50
                                    : null,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('Error: $error')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
