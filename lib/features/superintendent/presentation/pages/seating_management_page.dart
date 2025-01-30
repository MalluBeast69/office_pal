import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'seating_arrangement/select_exam_page.dart';
import 'dart:developer' as developer;

class SeatingManagementPage extends ConsumerStatefulWidget {
  const SeatingManagementPage({super.key});

  @override
  ConsumerState<SeatingManagementPage> createState() =>
      _SeatingManagementPageState();
}

class _SeatingManagementPageState extends ConsumerState<SeatingManagementPage> {
  bool _isLoading = true;
  bool _isCalendarVisible = true;
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupedArrangements =
      {};
  Map<String, Map<String, List<Map<String, dynamic>>>> _filteredArrangements =
      {};

  // Search and filter states
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String? _selectedSession;
  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSeatingArrangements();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final searchQuery = _searchController.text.toLowerCase();

    // Start with all arrangements
    Map<String, Map<String, List<Map<String, dynamic>>>> filtered = {};

    _groupedArrangements.forEach((date, sessions) {
      // Apply date filter
      if (_selectedStartDate != null) {
        final examDate = DateTime.parse(date);
        final startDate = DateTime(_selectedStartDate!.year,
            _selectedStartDate!.month, _selectedStartDate!.day);
        final endDate = DateTime(_selectedEndDate!.year,
            _selectedEndDate!.month, _selectedEndDate!.day);

        if (!examDate.isAtSameMomentAs(startDate)) {
          return;
        }
      }

      // Filter sessions
      Map<String, List<Map<String, dynamic>>> filteredSessions = {};
      sessions.forEach((session, arrangements) {
        // Apply session filter
        if (_selectedSession != null && session != _selectedSession) {
          return;
        }

        // Apply search filter
        final filteredArrangements = arrangements.where((arrangement) {
          final exam = arrangement['exam'];
          return exam['course_id']
              .toString()
              .toLowerCase()
              .contains(searchQuery);
        }).toList();

        if (filteredArrangements.isNotEmpty) {
          filteredSessions[session] = filteredArrangements;
        }
      });

      if (filteredSessions.isNotEmpty) {
        filtered[date] = filteredSessions;
      }
    });

    setState(() {
      _filteredArrangements = filtered;
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2025),
      initialDateRange: _selectedStartDate != null && _selectedEndDate != null
          ? DateTimeRange(start: _selectedStartDate!, end: _selectedEndDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked.start;
        _selectedEndDate = picked.end;
      });
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedStartDate = null;
      _selectedEndDate = null;
      _selectedSession = null;
      _filteredArrangements = Map.from(_groupedArrangements);
    });
  }

  Future<void> _loadSeatingArrangements() async {
    try {
      setState(() => _isLoading = true);

      // Load all seating arrangements with exam details
      final response =
          await Supabase.instance.client.from('seating_arr').select('''
            *,
            exam:exam_id (
              exam_id,
              course_id,
              exam_date,
              session,
              time,
              duration
            )
          ''').order('created_at', ascending: false);

      // Group arrangements by date and session
      final arrangements = List<Map<String, dynamic>>.from(response);
      final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

      for (final arrangement in arrangements) {
        final exam = arrangement['exam'] as Map<String, dynamic>;
        final date = exam['exam_date'].toString().split(' ')[0];
        final session = exam['session'] as String;

        grouped[date] ??= {};
        grouped[date]![session] ??= [];
        grouped[date]![session]!.add(arrangement);
      }

      if (mounted) {
        setState(() {
          _groupedArrangements = grouped;
          _filteredArrangements = Map.from(grouped);
          _isLoading = false;
        });
      }
    } catch (error) {
      developer.log('Error loading seating arrangements: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading seating arrangements: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSeatingArrangement(String examId) async {
    try {
      setState(() => _isLoading = true);

      // Delete seating arrangement
      await Supabase.instance.client
          .from('seating_arr')
          .delete()
          .eq('exam_id', examId);

      await _loadSeatingArrangements();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seating arrangement deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      developer.log('Error deleting seating arrangement: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting seating arrangement: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create a set of dates that have exams
    final examDates =
        _groupedArrangements.keys.map((date) => DateTime.parse(date)).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seating Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSeatingArrangements,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Search and Filter Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Calendar Toggle
                        Row(
                          children: [
                            Text(
                              'Calendar View',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (_selectedStartDate != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Text(
                                  'Selected: ${DateFormat('MMM d').format(_selectedStartDate!)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ),
                            IconButton(
                              icon: Icon(_isCalendarVisible
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                              onPressed: () {
                                setState(() {
                                  _isCalendarVisible = !_isCalendarVisible;
                                });
                              },
                            ),
                          ],
                        ),
                        // Calendar Instructions
                        if (_isCalendarVisible && _selectedStartDate == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withOpacity(0.3),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Select a date to view seating arrangements for that day',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Calendar View
                        if (_isCalendarVisible)
                          Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: TableCalendar(
                              firstDay: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDay:
                                  DateTime.now().add(const Duration(days: 365)),
                              focusedDay: _focusedDay,
                              selectedDayPredicate: (day) {
                                if (_selectedStartDate == null) return false;
                                return isSameDay(day, _selectedStartDate!);
                              },
                              calendarFormat: CalendarFormat.month,
                              eventLoader: (day) {
                                // Return a single event if the day has exams
                                if (examDates.contains(
                                    DateTime(day.year, day.month, day.day))) {
                                  return ['exam'];
                                }
                                return [];
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                setState(() {
                                  _selectedStartDate = DateTime(
                                      selectedDay.year,
                                      selectedDay.month,
                                      selectedDay.day);
                                  _selectedEndDate = DateTime(selectedDay.year,
                                      selectedDay.month, selectedDay.day);
                                  _focusedDay = focusedDay;
                                });
                                _applyFilters();
                              },
                              onPageChanged: (focusedDay) {
                                setState(() {
                                  _focusedDay = focusedDay;
                                });
                              },
                              calendarStyle: CalendarStyle(
                                markerDecoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                todayDecoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                markersMaxCount: 1,
                                markerSize: 6,
                                markersAlignment: Alignment.bottomCenter,
                              ),
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Search and Filters Row
                        Row(
                          children: [
                            // Search Bar
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: _selectedStartDate == null
                                      ? 'First select a date from the calendar...'
                                      : 'Search by course code...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor:
                                      Theme.of(context).colorScheme.surface,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 16),
                                ),
                                onChanged: (value) => _applyFilters(),
                                enabled: _selectedStartDate != null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Session Filter
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(
                                        _selectedStartDate == null ? 0.5 : 1,
                                      ),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: DropdownButton<String>(
                                value: _selectedSession,
                                hint: const Text('Session'),
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('All Sessions'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'AN',
                                    child: Text('AN'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'FN',
                                    child: Text('FN'),
                                  ),
                                ],
                                onChanged: _selectedStartDate == null
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _selectedSession = value;
                                        });
                                        _applyFilters();
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Clear Filters
                            TextButton.icon(
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear'),
                              onPressed: _clearFilters,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Create New Arrangement'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SelectExamPage(),
                                ),
                              ).then((_) => _loadSeatingArrangements());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // List of seating arrangements
                  _filteredArrangements.isEmpty
                      ? SizedBox(
                          height: 200,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_seat_outlined,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No seating arrangements found',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                if (_searchController.text.isEmpty &&
                                    _selectedStartDate == null &&
                                    _selectedSession == null)
                                  Text(
                                    'Create a new seating arrangement to get started',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  )
                                else
                                  Text(
                                    'Try adjusting your filters',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredArrangements.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, dateIndex) {
                            final date =
                                _filteredArrangements.keys.elementAt(dateIndex);
                            final sessions = _filteredArrangements[date]!;
                            final firstExam =
                                sessions.values.first.first['exam'];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    DateFormat('MMMM d, y')
                                        .format(DateTime.parse(date)),
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                ...sessions.entries.map((sessionEntry) {
                                  final session = sessionEntry.key;
                                  final arrangements = sessionEntry.value;
                                  final firstExam = arrangements.first['exam'];

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ListTile(
                                          title: Text('Session: $session'),
                                          subtitle: Text(
                                              'Time: ${firstExam['time']}'),
                                          leading: const Icon(Icons.schedule),
                                        ),
                                        const Divider(),
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Exams in this session:',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                              const SizedBox(height: 8),
                                              ...arrangements
                                                  .map((arrangement) {
                                                final exam =
                                                    arrangement['exam'];
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 8),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.book,
                                                          size: 16),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          '${exam['course_id']} (${exam['duration']} mins)',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        ),
                                        ButtonBar(
                                          children: [
                                            TextButton.icon(
                                              icon:
                                                  const Icon(Icons.visibility),
                                              label: const Text('View'),
                                              onPressed: () {
                                                // TODO: Navigate to view seating arrangement
                                              },
                                            ),
                                            TextButton.icon(
                                              icon: const Icon(Icons.edit),
                                              label: const Text('Edit'),
                                              onPressed: () {
                                                // TODO: Navigate to edit seating arrangement
                                              },
                                            ),
                                            TextButton.icon(
                                              icon: const Icon(Icons.delete),
                                              label: const Text('Delete'),
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                    title: const Text(
                                                        'Delete Arrangement'),
                                                    content: Text(
                                                      'Are you sure you want to delete the seating arrangement for ${DateFormat('MMMM d, y').format(DateTime.parse(date))} - $session?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context),
                                                        child: const Text(
                                                            'Cancel'),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () {
                                                          Navigator.pop(
                                                              context);
                                                          // Delete all arrangements for this session
                                                          for (final arr
                                                              in arrangements) {
                                                            _deleteSeatingArrangement(
                                                                arr['exam'][
                                                                    'exam_id']);
                                                          }
                                                        },
                                                        child: const Text(
                                                            'Delete'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}
