import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
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
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

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

  // Helper method to get exam dates
  Set<DateTime> _getExamDates(List<Map<String, dynamic>> exams) {
    return exams.map((exam) => DateTime.parse(exam['exam_date'])).toSet();
  }

  // Helper method to check if a day has exams
  bool _hasExamsOnDay(DateTime day, Set<DateTime> examDates) {
    return examDates.any((examDate) =>
        examDate.year == day.year &&
        examDate.month == day.month &&
        examDate.day == day.day);
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
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: allSelected
                        ? Theme.of(context).colorScheme.error.withOpacity(0.9)
                        : Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: allSelected
                        ? Theme.of(context).colorScheme.onError
                        : Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  icon: Icon(
                    allSelected ? Icons.deselect : Icons.select_all,
                  ),
                  label: Text(
                    allSelected ? 'Deselect All' : 'Select All',
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
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(180),
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
                DropdownButtonFormField<String>(
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
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Card(
                    margin: const EdgeInsets.all(16.0),
                    child: TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) {
                        return _selectedDate != null &&
                            isSameDay(_selectedDate!, day);
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDate = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
                      onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          final exams = ref.watch(examsProvider).value ?? [];
                          final examDates = _getExamDates(exams);
                          if (_hasExamsOnDay(date, examDates)) {
                            return Positioned(
                              bottom: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                width: 6.0,
                                height: 6.0,
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  examsAsync.when(
                    data: (exams) {
                      final filteredExams = _filterExams(exams);

                      if (filteredExams.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('No exams found'),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: $error'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
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
      ),
    );
  }
}
