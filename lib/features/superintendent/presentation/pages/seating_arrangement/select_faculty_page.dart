import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'preview_seating_page.dart';
import 'dart:developer' as developer;

class SelectFacultyPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;
  final List<String> selectedStudents;
  final List<String> selectedHalls;

  const SelectFacultyPage({
    super.key,
    required this.exams,
    required this.selectedStudents,
    required this.selectedHalls,
  });

  @override
  ConsumerState<SelectFacultyPage> createState() => _SelectFacultyPageState();
}

class _SelectFacultyPageState extends ConsumerState<SelectFacultyPage> {
  List<Map<String, dynamic>> _faculty = [];
  Map<String, String> _hallFacultyMap = {};
  bool _isLoading = false;
  String _searchQuery = '';
  late int _requiredFaculty;
  // Track hall-session combinations
  Map<String, Set<String>> _hallSessionsMap = {};
  // Track unique hall-session pairs that need faculty
  Set<String> _uniqueHallSessionPairs = {};

  @override
  void initState() {
    super.initState();
    _initializeHallSessions();
    _loadFaculty();
  }

  Future<void> _loadFaculty() async {
    setState(() => _isLoading = true);
    try {
      // Load faculty with their existing assignments
      final response = await Supabase.instance.client.from('faculty').select('''
            *,
            seating_arr:seating_arr(
              exam_id,
              hall_id,
              exam:exam(exam_date, session)
            )
          ''').eq('is_available', true);

      if (mounted) {
        setState(() {
          _faculty = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading faculty: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Calculate faculty workload for a given date
  int _getFacultyWorkload(Map<String, dynamic> faculty, DateTime date) {
    final assignments = (faculty['seating_arr'] as List?) ?? [];
    return assignments.where((assignment) {
      final examDate = DateTime.parse(assignment['exam']['exam_date']);
      return examDate.year == date.year &&
          examDate.month == date.month &&
          examDate.day == date.day;
    }).length;
  }

  // Get faculty availability score (lower is better)
  double _getFacultyScore(Map<String, dynamic> faculty, DateTime examDate) {
    final workload = _getFacultyWorkload(faculty, examDate);
    final assignments = (faculty['seating_arr'] as List?) ?? [];

    // Calculate average workload over the past week
    int weeklyWorkload = 0;
    for (int i = 1; i <= 7; i++) {
      final date = examDate.subtract(Duration(days: i));
      weeklyWorkload += _getFacultyWorkload(faculty, date);
    }

    // Score based on current day workload and weekly average
    return workload * 2.0 + (weeklyWorkload / 7.0);
  }

  // Initialize hall sessions map and calculate required faculty
  void _initializeHallSessions() {
    _hallSessionsMap.clear();
    _uniqueHallSessionPairs.clear();

    // Group exams by date
    final examsByDate = <String, List<Map<String, dynamic>>>{};
    for (final exam in widget.exams) {
      final date = exam['exam_date'].toString().split(' ')[0];
      examsByDate[date] ??= [];
      examsByDate[date]!.add(exam);
    }

    // For each date, process sessions
    for (final date in examsByDate.keys) {
      final dateExams = examsByDate[date]!;
      final sessions = dateExams.map((e) => e['session'] as String).toSet();

      for (final session in sessions) {
        // For each hall, check if it's needed for this session
        for (final hallId in widget.selectedHalls) {
          // Create a unique identifier for this hall-session combination
          final hallSessionKey = '$hallId|$session|$date';

          // If this hall is needed for this session
          if (dateExams.any((exam) => exam['session'] == session)) {
            _hallSessionsMap[hallId] ??= {};
            _hallSessionsMap[hallId]!.add(session);
            _uniqueHallSessionPairs.add(hallSessionKey);
          }
        }
      }
    }

    // Update required faculty count based on unique hall-session pairs
    _requiredFaculty = _uniqueHallSessionPairs.length;
    developer.log('Required faculty count: $_requiredFaculty');
    developer.log('Hall sessions map: $_hallSessionsMap');
    developer.log('Unique hall-session pairs: $_uniqueHallSessionPairs');
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

  void _autoAssignFaculty() {
    final availableFaculty = _filterFaculty();
    if (availableFaculty.isEmpty) return;

    _hallFacultyMap.clear();

    // Group exams by date
    final examsByDate = <String, List<Map<String, dynamic>>>{};
    for (final exam in widget.exams) {
      final date = exam['exam_date'].toString().split(' ')[0];
      examsByDate[date] ??= [];
      examsByDate[date]!.add(exam);
    }

    // For each date
    for (final date in examsByDate.keys) {
      final dateExams = examsByDate[date]!;
      final sessions = dateExams.map((e) => e['session'] as String).toSet();

      // For each session
      for (final session in sessions) {
        // Get halls needed for this session
        final sessionHalls = widget.selectedHalls.where((hallId) {
          return _hallSessionsMap[hallId]?.contains(session) ?? false;
        }).toList();

        // Sort faculty by availability
        final sortedFaculty = List<Map<String, dynamic>>.from(availableFaculty)
          ..sort((a, b) {
            final scoreA = _getFacultyScore(a, DateTime.parse(date));
            final scoreB = _getFacultyScore(b, DateTime.parse(date));
            return scoreA.compareTo(scoreB);
          });

        // Assign faculty to halls
        for (final hallId in sessionHalls) {
          final hallSessionKey = '$hallId|$session|$date';

          // Find available faculty for this hall-session
          final availableFacultyForHall = sortedFaculty.where((f) {
            final facultyId = f['faculty_id'];

            // Check if this faculty is already assigned to another hall in the same session and date
            for (final existingKey in _hallFacultyMap.keys) {
              if (_hallFacultyMap[existingKey] == facultyId) {
                final parts = existingKey.split('|');
                if (parts.length >= 3) {
                  final existingSession = parts[1];
                  final existingDate = parts[2];
                  // Can't assign if already assigned to same session on same date
                  if (existingSession == session && existingDate == date) {
                    return false;
                  }
                }
              }
            }
            return true;
          }).toList();

          if (availableFacultyForHall.isNotEmpty) {
            _hallFacultyMap[hallSessionKey] =
                availableFacultyForHall.first['faculty_id'];
          }
        }
      }
    }

    setState(() {});
  }

  List<Map<String, dynamic>> _filterFaculty() {
    return _faculty.where((faculty) {
      // Search filter
      final facultyId = faculty['faculty_id']?.toString().toLowerCase() ?? '';
      final facultyName =
          faculty['faculty_name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      return facultyId.contains(searchLower) ||
          facultyName.contains(searchLower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaculty = _filterFaculty();

    // Group halls by date and session
    final hallsByDateAndSession = <String, Map<String, List<String>>>{};

    for (final hallId in widget.selectedHalls) {
      final sessions = _hallSessionsMap[hallId] ?? {};

      for (final exam in widget.exams) {
        final date = exam['exam_date'].toString().split(' ')[0];
        final session = exam['session'] as String;

        if (sessions.contains(session)) {
          hallsByDateAndSession[date] ??= {};
          hallsByDateAndSession[date]![session] ??= [];
          if (!hallsByDateAndSession[date]![session]!.contains(hallId)) {
            hallsByDateAndSession[date]![session]!.add(hallId);
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Faculty'),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Auto Assign'),
            onPressed: _autoAssignFaculty,
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
                    hintText: 'Search by faculty ID or name',
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _hallFacultyMap.length >= _requiredFaculty
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hallFacultyMap.length >= _requiredFaculty
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _hallFacultyMap.length >= _requiredFaculty
                            ? Icons.check_circle
                            : Icons.warning,
                        color: _hallFacultyMap.length >= _requiredFaculty
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Assigned: ${_hallFacultyMap.length} / $_requiredFaculty faculty needed',
                        style: TextStyle(
                          color: _hallFacultyMap.length >= _requiredFaculty
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
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
                Expanded(
                  child: ListView.builder(
                    itemCount: hallsByDateAndSession.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, dateIndex) {
                      final date =
                          hallsByDateAndSession.keys.elementAt(dateIndex);
                      final sessionsMap = hallsByDateAndSession[date]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Date: $date',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ...sessionsMap.entries.map((sessionEntry) {
                            final session = sessionEntry.key;
                            final halls = sessionEntry.value;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _getSessionDisplayName(session),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                ...halls.map((hallId) {
                                  final hallSessionKey =
                                      '$hallId|$session|$date';
                                  final assignedFacultyId =
                                      _hallFacultyMap[hallSessionKey];
                                  final assignedFaculty = assignedFacultyId !=
                                          null
                                      ? _faculty.firstWhere((f) =>
                                          f['faculty_id'] == assignedFacultyId)
                                      : null;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(hallId),
                                      subtitle: Text(assignedFaculty != null
                                          ? '${assignedFaculty['faculty_name']} (${assignedFaculty['faculty_id']})'
                                          : 'No faculty assigned'),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (facultyId) {
                                          setState(() {
                                            if (facultyId.isNotEmpty) {
                                              _hallFacultyMap[hallSessionKey] =
                                                  facultyId;
                                            } else {
                                              _hallFacultyMap
                                                  .remove(hallSessionKey);
                                            }
                                          });
                                        },
                                        itemBuilder: (context) => [
                                          if (assignedFacultyId != null)
                                            const PopupMenuItem(
                                              value: '',
                                              child: Text('Remove Assignment'),
                                            ),
                                          ...filteredFaculty.where((f) {
                                            final facultyId = f['faculty_id'];

                                            // Check if faculty is already assigned to another hall in this session and date
                                            for (final existingKey
                                                in _hallFacultyMap.keys) {
                                              if (_hallFacultyMap[
                                                      existingKey] ==
                                                  facultyId) {
                                                final parts =
                                                    existingKey.split('|');
                                                if (parts.length >= 3) {
                                                  final existingSession =
                                                      parts[1];
                                                  final existingDate = parts[2];
                                                  if (existingSession ==
                                                          session &&
                                                      existingDate == date) {
                                                    return false;
                                                  }
                                                }
                                              }
                                            }
                                            return true;
                                          }).map(
                                            (faculty) => PopupMenuItem(
                                              value: faculty['faculty_id'],
                                              child: Text(
                                                  '${faculty['faculty_name']} (${faculty['faculty_id']})'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 16),
                              ],
                            );
                          }).toList(),
                          const Divider(height: 32),
                        ],
                      );
                    },
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
                                'Faculty Assignments',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${_hallFacultyMap.length} of $_requiredFaculty assignments completed',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                          onPressed: _hallFacultyMap.length >= _requiredFaculty
                              ? () {
                                  // Convert hall-session-date keys back to hall-faculty mapping
                                  final simplifiedMap = <String, String>{};
                                  for (final entry in _hallFacultyMap.entries) {
                                    final hallId = entry.key.split('|')[0];
                                    simplifiedMap[hallId] = entry.value;
                                  }

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PreviewSeatingPage(
                                        exams: widget.exams,
                                        selectedStudents:
                                            widget.selectedStudents,
                                        selectedHalls: widget.selectedHalls,
                                        hallFacultyMap: simplifiedMap,
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
