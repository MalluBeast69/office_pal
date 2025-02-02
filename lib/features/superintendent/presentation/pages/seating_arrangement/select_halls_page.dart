import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'select_faculty_page.dart';
import 'dart:developer' as developer;

class SelectHallsPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;
  final List<String> selectedStudents;

  const SelectHallsPage({
    super.key,
    required this.exams,
    required this.selectedStudents,
  });

  @override
  ConsumerState<SelectHallsPage> createState() => _SelectHallsPageState();
}

class _SelectHallsPageState extends ConsumerState<SelectHallsPage> {
  List<Map<String, dynamic>> _halls = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, Set<String>> _selectedHallsBySession = {};
  Map<String, Map<String, int>> _capacityNeededPerDateAndSession = {};
  int _maxCapacityNeeded = 0;
  String? _selectedDepartment;
  List<String> _departments = [];
  String? _selectedSession;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // Load registered students data first
      final registeredStudentsResponse =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            course_code,
            is_reguler
          ''').in_('student_reg_no', widget.selectedStudents);

      final registeredStudents =
          List<Map<String, dynamic>>.from(registeredStudentsResponse);
      developer.log('Loaded ${registeredStudents.length} registered students');

      // Group students by date and session, tracking unique students
      final studentsByDateAndSession =
          <String, Map<String, Map<String, Set<String>>>>{};

      for (final exam in widget.exams) {
        final date = exam['exam_date'].toString().split(' ')[0];
        final session = exam['session'] as String;
        final courseId = exam['course_id'] as String;

        developer.log('Processing exam: $courseId on $date, session: $session');

        studentsByDateAndSession[date] ??= {};
        studentsByDateAndSession[date]![session] ??= {
          'regular': <String>{},
          'supplementary': <String>{},
          'all': <String>{}, // Track all students regardless of type
        };

        // Find students registered for this course
        final examStudents =
            registeredStudents.where((s) => s['course_code'] == courseId);

        var regularCount = 0;
        var supplementaryCount = 0;

        // Add students to sets to ensure uniqueness
        for (final student in examStudents) {
          final studentId = student['student_reg_no'] as String;
          final isRegular = student['is_reguler'] as bool;

          // Only count if student hasn't been added to either category
          if (!studentsByDateAndSession[date]![session]!['all']!
              .contains(studentId)) {
            studentsByDateAndSession[date]![session]!['all']!.add(studentId);

            if (isRegular) {
              studentsByDateAndSession[date]![session]!['regular']!
                  .add(studentId);
              regularCount++;
            } else {
              studentsByDateAndSession[date]![session]!['supplementary']!
                  .add(studentId);
              supplementaryCount++;
            }
          }
        }

        developer.log(
            'Students for exam $courseId: Regular: $regularCount, Supplementary: $supplementaryCount');
      }

      // Calculate capacity needed for each date and session
      _capacityNeededPerDateAndSession = {};
      for (var dateEntry in studentsByDateAndSession.entries) {
        final date = dateEntry.key;
        _capacityNeededPerDateAndSession[date] = {};

        for (var sessionEntry in dateEntry.value.entries) {
          final session = sessionEntry.key;
          final regularStudents = sessionEntry.value['regular']!;
          final supplementaryStudents = sessionEntry.value['supplementary']!;
          final allStudents = sessionEntry.value['all']!;

          final totalRegular = regularStudents.length;
          final totalSupplementary = supplementaryStudents.length;
          final totalStudents = allStudents.length;

          // Store actual student count
          _capacityNeededPerDateAndSession[date]![session] = totalStudents;

          developer.log('Session $session total students: $totalStudents ' +
              '(Regular: $totalRegular, Supplementary: $totalSupplementary)');
          developer
              .log('Regular students: ${regularStudents.toList().join(", ")}');
          developer.log(
              'Supplementary students: ${supplementaryStudents.toList().join(", ")}');
          developer
              .log('All unique students: ${allStudents.toList().join(", ")}');
        }
      }

      // Load halls data
      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true);

      setState(() {
        _halls = List<Map<String, dynamic>>.from(hallsResponse);
        _departments = _halls
            .map((h) => h['hall_dept'] as String)
            .toSet()
            .toList()
          ..sort();
        _isLoading = false;

        // Initialize selected halls for each session
        _selectedHallsBySession = {};
        for (final dateEntry in _capacityNeededPerDateAndSession.entries) {
          for (final sessionEntry in dateEntry.value.entries) {
            _selectedHallsBySession[sessionEntry.key] = {};
          }
        }

        // Set initial selected session
        if (_capacityNeededPerDateAndSession.isNotEmpty) {
          final firstDate = _capacityNeededPerDateAndSession.keys.first;
          if (_capacityNeededPerDateAndSession[firstDate]?.isNotEmpty ??
              false) {
            _selectedSession =
                _capacityNeededPerDateAndSession[firstDate]!.keys.first;
            developer.log('Initial selected session: $_selectedSession');
          }
        }
      });
    } catch (error) {
      developer.log('Error loading data: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _filterAndSortHalls() {
    final filtered = _halls.where((hall) {
      // Search filter
      final hallId = hall['hall_id']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      if (!hallId.contains(searchLower)) {
        return false;
      }

      // Department filter
      if (_selectedDepartment != null &&
          hall['hall_dept'] != _selectedDepartment) {
        return false;
      }

      return true;
    }).toList();

    // Sort halls by department and capacity
    filtered.sort((a, b) {
      // First sort by department to keep halls from same department together
      final deptCompare =
          (a['hall_dept'] as String).compareTo(b['hall_dept'] as String);
      if (deptCompare != 0) return deptCompare;

      // Then sort by capacity (larger halls first)
      return (b['capacity'] as int).compareTo(a['capacity'] as int);
    });

    return filtered;
  }

  int _getSelectedCapacityForSession(String session) {
    final halls = _selectedHallsBySession[session] ?? <String>{};
    return halls.fold(0, (sum, hallId) {
      final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
      return sum + (hall['capacity'] as int);
    });
  }

  int _getCapacityNeededForSession(String session) {
    // Find the maximum capacity needed for this session across all dates
    int maxCapacity = 0;
    developer.log('Calculating capacity needed for session: $session');

    for (final dateEntry in _capacityNeededPerDateAndSession.entries) {
      final sessionCapacity = dateEntry.value[session] ?? 0;
      if (sessionCapacity > maxCapacity) {
        maxCapacity = sessionCapacity;
      }
    }

    developer.log('Total students for $session session: $maxCapacity');
    return maxCapacity;
  }

  String _getSessionDisplayName(String session) {
    switch (session) {
      case 'MORNING':
        return 'Morning';
      case 'AFTERNOON':
        return 'Afternoon';
      case 'EVENING':
        return 'Evening';
      default:
        return session;
    }
  }

  void _selectHall(String hallId, bool selected) {
    if (_selectedSession == null) return;

    final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
    setState(() {
      if (selected) {
        _selectedHallsBySession[_selectedSession]?.add(hallId);
      } else {
        _selectedHallsBySession[_selectedSession]?.remove(hallId);
      }
    });
  }

  void _autoSelectHalls() {
    developer.log('Auto-selecting halls for all sessions');

    // Get all unique sessions
    final allSessions = _capacityNeededPerDateAndSession.values
        .expand((sessions) => sessions.keys)
        .toSet()
        .toList();

    // Clear all current selections
    setState(() {
      for (final session in allSessions) {
        _selectedHallsBySession[session] = {};
      }

      // Store current session
      final currentSession = _selectedSession;

      // Process each session
      for (final session in allSessions) {
        // Temporarily set the current session for _selectHall to work
        _selectedSession = session;
        _autoSelectHallsForSession(session);
      }

      // Restore the original selected session
      _selectedSession = currentSession;
    });
  }

  void _autoSelectHallsForSession(String session) {
    developer.log('Auto-selecting halls for session: $session');

    // Get filtered and sorted halls by capacity
    final availableHalls = _filterAndSortHalls()
      ..sort((a, b) => (b['capacity'] as int).compareTo(a['capacity'] as int));
    developer.log('Available halls: ${availableHalls.length}');

    // Calculate total students for this session
    final totalStudents = _getCapacityNeededForSession(session);

    // Always select the two largest halls for even distribution
    final selectedHalls = <Map<String, dynamic>>[
      availableHalls[0], // First largest hall (AC102)
      availableHalls[1], // Second largest hall (EE301)
    ];

    // Calculate total available capacity
    final totalCapacity = selectedHalls.fold<int>(
        0, (sum, hall) => sum + (hall['capacity'] as int));

    // Calculate target students per hall for even distribution
    final targetPerHall = (totalStudents / 2).ceil();

    developer.log('Total students to seat: $totalStudents');
    developer.log('Target students per hall: $targetPerHall');
    developer.log(
        'Selected halls: ${selectedHalls.map((h) => "${h['hall_id']} (${h['capacity']})").join(", ")}');
    developer.log('Total capacity: $totalCapacity');

    // Select both halls
    for (final hall in selectedHalls) {
      _selectHall(hall['hall_id'], true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredHalls = _filterAndSortHalls();
    final currentSessionCapacity = _selectedSession != null
        ? _getSelectedCapacityForSession(_selectedSession!)
        : 0;
    final currentSessionNeeded = _selectedSession != null
        ? _getCapacityNeededForSession(_selectedSession!)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Halls'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text(
                'Auto Select',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: _selectedSession != null ? _autoSelectHalls : null,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(280),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Session selection chips
                Wrap(
                  spacing: 8,
                  children: _capacityNeededPerDateAndSession.values
                      .expand((sessions) => sessions.keys)
                      .toSet()
                      .map((session) {
                    final isSelected = _selectedSession == session;
                    return FilterChip(
                      selected: isSelected,
                      label: Text(_getSessionDisplayName(session)),
                      onSelected: (selected) {
                        setState(
                            () => _selectedSession = selected ? session : null);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by hall ID',
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
                    ..._departments.map((dept) => DropdownMenuItem(
                          value: dept,
                          child: Text(dept),
                        )),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedDepartment = value),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: currentSessionCapacity >= currentSessionNeeded
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentSessionCapacity >= currentSessionNeeded
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (_selectedSession != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              currentSessionCapacity >= currentSessionNeeded
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color:
                                  currentSessionCapacity >= currentSessionNeeded
                                      ? Colors.green
                                      : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Capacity Needed: $currentSessionNeeded',
                              style: TextStyle(
                                color: currentSessionCapacity >=
                                        currentSessionNeeded
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selected Capacity: $currentSessionCapacity',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      ..._capacityNeededPerDateAndSession.entries.map(
                        (dateEntry) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateEntry.key,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Wrap(
                              spacing: 8,
                              children:
                                  dateEntry.value.entries.map((sessionEntry) {
                                final isCurrentSession =
                                    sessionEntry.key == _selectedSession;
                                return Chip(
                                  label: Text(
                                    '${_getSessionDisplayName(sessionEntry.key)}: ${sessionEntry.value}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrentSession
                                          ? FontWeight.bold
                                          : null,
                                    ),
                                  ),
                                  backgroundColor: isCurrentSession
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceVariant,
                                  labelStyle: TextStyle(
                                    color: isCurrentSession
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_selectedSession == null)
                  const Expanded(
                    child: Center(
                      child: Text('Please select a session to continue'),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 1200
                                  ? 4
                                  : MediaQuery.of(context).size.width > 800
                                      ? 3
                                      : 2,
                          childAspectRatio: 1.5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: filteredHalls.length,
                        itemBuilder: (context, index) {
                          final hall = filteredHalls[index];
                          final hallId = hall['hall_id'];
                          final isSelected =
                              _selectedHallsBySession[_selectedSession]
                                      ?.contains(hallId) ??
                                  false;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withOpacity(0.5),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _selectHall(hallId, !isSelected),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                hallId,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                hall['hall_dept'],
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (value) => _selectHall(
                                              hallId, value ?? false),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Capacity: ${hall['capacity']}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${hall['no_of_columns']} × ${hall['no_of_rows']} seats',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Container(
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
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Selected Halls',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_selectedSession != null)
                                Text(
                                  '${_selectedHallsBySession[_selectedSession]?.length ?? 0} halls for ${_getSessionDisplayName(_selectedSession!)} session',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                          onPressed: _selectedHallsBySession.values.every(
                            (halls) {
                              final session = _selectedHallsBySession.entries
                                  .firstWhere((e) => e.value == halls)
                                  .key;
                              return _getSelectedCapacityForSession(session) >=
                                  _getCapacityNeededForSession(session);
                            },
                          )
                              ? () {
                                  // Combine all selected halls into a single list
                                  final allSelectedHalls =
                                      _selectedHallsBySession.values
                                          .expand((halls) => halls)
                                          .toList();

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SelectFacultyPage(
                                        exams: widget.exams,
                                        selectedStudents:
                                            widget.selectedStudents,
                                        selectedHalls: allSelectedHalls,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
