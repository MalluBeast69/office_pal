import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'preview_seating_page.dart';
import 'dart:developer' as developer;

class SelectFacultyPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;
  final List<String> selectedStudents;
  final List<Map<String, dynamic>> selectedHalls;

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

  // Calculate faculty workload for a given date and session
  int _getFacultyWorkload(
      Map<String, dynamic> faculty, DateTime date, String session) {
    final assignments = (faculty['seating_arr'] as List?) ?? [];
    return assignments.where((assignment) {
      final examDate = DateTime.parse(assignment['exam']['exam_date']);
      final examSession = assignment['exam']['session'] as String;
      return examDate.year == date.year &&
          examDate.month == date.month &&
          examDate.day == date.day &&
          examSession == session;
    }).length;
  }

  // Get faculty availability score (lower is better)
  double _getFacultyScore(
      Map<String, dynamic> faculty, DateTime examDate, String session) {
    final workload = _getFacultyWorkload(faculty, examDate, session);
    final assignments = (faculty['seating_arr'] as List?) ?? [];

    // Calculate average workload over the past week
    int weeklyWorkload = 0;
    for (int i = 1; i <= 7; i++) {
      final date = examDate.subtract(Duration(days: i));
      weeklyWorkload += _getFacultyWorkload(faculty, date, session);
    }

    // Check if faculty has another assignment on the same day
    bool hasOtherSessionToday = assignments.any((assignment) {
      final assignmentDate = DateTime.parse(assignment['exam']['exam_date']);
      final assignmentSession = assignment['exam']['session'] as String;
      return assignmentDate.year == examDate.year &&
          assignmentDate.month == examDate.month &&
          assignmentDate.day == examDate.day &&
          assignmentSession != session;
    });

    // Heavily penalize assigning faculty to multiple sessions on same day
    double sameDayPenalty = hasOtherSessionToday ? 100.0 : 0.0;

    // Score based on current session workload, weekly average, and same-day penalty
    return workload * 2.0 + (weeklyWorkload / 7.0) + sameDayPenalty;
  }

  // Initialize hall sessions map and calculate required faculty
  void _initializeHallSessions() {
    _hallSessionsMap.clear();
    _uniqueHallSessionPairs.clear();

    // First, initialize the hall sessions map
    for (final hall in widget.selectedHalls) {
      final hallId = hall['hall_id'].toString();
      _hallSessionsMap[hallId] = <String>{};
    }

    // For each hall, add its session from the selectedHalls data
    for (final hall in widget.selectedHalls) {
      final hallId = hall['hall_id'].toString();
      final session = hall['session'] as String;
      final date = hall['exam_date'].toString().split(' ')[0];

      // Add this session to the hall's set of sessions
      _hallSessionsMap[hallId]!.add(session);

      // Create and add the unique hall-session-date combination
      final hallSessionKey = '$hallId|$session|$date';
      _uniqueHallSessionPairs.add(hallSessionKey);

      developer.log('Added hall-session pair: $hallSessionKey');
    }

    // Update required faculty count based on unique hall-session pairs
    _requiredFaculty = _uniqueHallSessionPairs.length;

    // Log the final mappings for debugging
    developer.log('Required faculty count: $_requiredFaculty');
    for (final hallId in _hallSessionsMap.keys) {
      developer.log(
          'Hall $hallId sessions: ${_hallSessionsMap[hallId]!.join(", ")}');
    }
    developer.log(
        'Unique hall-session pairs: ${_uniqueHallSessionPairs.join(", ")}');
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

    // Track faculty assignments per date to avoid multiple sessions per day
    final facultyAssignmentsByDate = <String, Map<String, String>>{};

    // Sort faculty by workload (least busy first)
    final sortedFaculty = List<Map<String, dynamic>>.from(availableFaculty)
      ..sort((a, b) {
        final aAssignments = (a['seating_arr'] as List?)?.length ?? 0;
        final bAssignments = (b['seating_arr'] as List?)?.length ?? 0;
        return aAssignments.compareTo(bAssignments);
      });

    // Process each unique hall-session pair
    for (final hallSessionKey in _uniqueHallSessionPairs) {
      final parts = hallSessionKey.split('|');
      final hallId = parts[0];
      final session = parts[1];
      final date = parts[2];

      // Initialize tracking for this date if needed
      facultyAssignmentsByDate[date] ??= {};

      // Find available faculty for this session
      final availableFacultyForSession = sortedFaculty.where((faculty) {
        final facultyId = faculty['faculty_id'];

        // Check if faculty is already assigned to another session on this date
        if (facultyAssignmentsByDate[date]!.containsValue(facultyId)) {
          return false;
        }

        // Check existing assignments for conflicts
        final assignments = (faculty['seating_arr'] as List?) ?? [];
        return !assignments.any((assignment) {
          final assignmentDate =
              assignment['exam']['exam_date'].toString().split(' ')[0];
          final assignmentSession = assignment['exam']['session'];
          return assignmentDate == date && assignmentSession == session;
        });
      }).toList();

      if (availableFacultyForSession.isNotEmpty) {
        // Select the faculty with the least workload
        final selectedFaculty = availableFacultyForSession.first;
        _hallFacultyMap[hallSessionKey] = selectedFaculty['faculty_id'];
        facultyAssignmentsByDate[date]![hallSessionKey] =
            selectedFaculty['faculty_id'];

        developer.log(
            'Assigned faculty ${selectedFaculty['faculty_name']} (${selectedFaculty['faculty_id']}) to $hallSessionKey');
      } else {
        developer.log('No available faculty for $hallSessionKey');
      }
    }

    setState(() {});
  }

  Future<void> _updateFacultyAvailability() async {
    try {
      // Get all faculty IDs that have been assigned
      final assignedFacultyIds = _hallFacultyMap.values.toSet();

      // Update is_available to false for assigned faculty
      await Supabase.instance.client
          .from('faculty')
          .update({'is_available': false}).in_(
              'faculty_id', assignedFacultyIds.toList());

      developer.log(
          'Updated availability for ${assignedFacultyIds.length} faculty members');
    } catch (error) {
      developer.log('Error updating faculty availability: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating faculty availability: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

    for (final hallId in widget.selectedHalls.map((e) => e['hall_id'])) {
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
                                  if (mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PreviewSeatingPage(
                                          exams: widget.exams,
                                          selectedStudents:
                                              widget.selectedStudents,
                                          selectedHalls: widget.selectedHalls,
                                          hallFacultyMap: _hallFacultyMap,
                                        ),
                                      ),
                                    );
                                  }
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
