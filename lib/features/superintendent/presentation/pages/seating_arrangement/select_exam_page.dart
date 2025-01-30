import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'select_students_page.dart';

class SelectExamPage extends ConsumerStatefulWidget {
  const SelectExamPage({super.key});

  @override
  ConsumerState<SelectExamPage> createState() => _SelectExamPageState();
}

class _SelectExamPageState extends ConsumerState<SelectExamPage> {
  String _searchQuery = '';
  DateTime? _selectedDate;
  String? _selectedSession;
  Set<Map<String, dynamic>> _selectedExams = {};

  List<Map<String, dynamic>> _filterExams(List<Map<String, dynamic>> exams) {
    return exams.where((exam) {
      // Search filter
      final courseId = exam['course_id']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      if (!courseId.contains(searchLower)) {
        return false;
      }

      // Date filter
      if (_selectedDate != null) {
        final examDate = DateTime.parse(exam['exam_date']);
        if (examDate.year != _selectedDate!.year ||
            examDate.month != _selectedDate!.month ||
            examDate.day != _selectedDate!.day) {
          return false;
        }
      }

      // Session filter
      if (_selectedSession != null) {
        final session = exam['session']?.toString() ?? '';
        if (session != _selectedSession) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Exams'),
        actions: [
          examsAsync.when(
            data: (exams) {
              final filteredExams = _filterExams(exams);
              final allSelected = filteredExams.every((exam) =>
                  _selectedExams.any((e) => e['exam_id'] == exam['exam_id']));
              return TextButton.icon(
                icon: Icon(
                  allSelected ? Icons.deselect : Icons.select_all,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                label: Text(
                  allSelected ? 'Deselect All' : 'Select All',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    if (allSelected) {
                      _selectedExams.clear();
                    } else {
                      _selectedExams = Set.from(filteredExams);
                    }
                  });
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by course code',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_selectedDate == null
                            ? 'Select Date'
                            : DateFormat('MMM d, y').format(_selectedDate!)),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() => _selectedDate = date);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSession,
                        decoration: const InputDecoration(
                          labelText: 'Session',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('All Sessions'),
                          ),
                          DropdownMenuItem(
                            value: 'MORNING',
                            child: Text('Morning'),
                          ),
                          DropdownMenuItem(
                            value: 'AFTERNOON',
                            child: Text('Afternoon'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedSession = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: examsAsync.when(
        data: (exams) {
          final filteredExams = _filterExams(exams);

          if (filteredExams.isEmpty) {
            return const Center(
              child: Text('No exams found'),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: filteredExams.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final exam = filteredExams[index];
                    final examDate = DateTime.parse(exam['exam_date']);
                    final isSelected = _selectedExams
                        .any((e) => e['exam_id'] == exam['exam_id']);

                    return Card(
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedExams.add(exam);
                            } else {
                              _selectedExams.removeWhere(
                                  (e) => e['exam_id'] == exam['exam_id']);
                            }
                          });
                        },
                        title: Text('${exam['course_id']}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Date: ${DateFormat('MMM d, y').format(examDate)}'),
                            Text(
                                'Session: ${exam['session']}, Time: ${exam['time']}, Duration: ${exam['duration']} mins'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected: ${_selectedExams.length} exams',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      onPressed: _selectedExams.isEmpty
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SelectStudentsPage(
                                    exams: _selectedExams.toList(),
                                  ),
                                ),
                              );
                            },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }
}
