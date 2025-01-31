import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'preview_seating_page.dart';

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

  @override
  void initState() {
    super.initState();
    _requiredFaculty = widget.selectedHalls.length;
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

  void _autoAssignFaculty() {
    final availableFaculty = _filterFaculty();
    if (availableFaculty.isEmpty) return;

    _hallFacultyMap.clear();

    // Get unique exam dates from widget.exams
    final examDates = widget.exams
        .map((e) => DateTime.parse(e['exam_date']))
        .toSet()
        .toList();

    // For each exam date
    for (final date in examDates) {
      // Get exams for this date
      final dateExams = widget.exams
          .where((e) => DateTime.parse(e['exam_date']).isAtSameMomentAs(date))
          .toList();

      // For each session in this date
      final sessions = dateExams.map((e) => e['session']).toSet();
      for (final session in sessions) {
        // Get halls that need faculty for this session
        final sessionHalls = widget.selectedHalls.where((hallId) {
          return dateExams.any((exam) => exam['session'] == session);
        }).toList();

        // Sort faculty by their availability score for this date
        final sortedFaculty = List<Map<String, dynamic>>.from(availableFaculty)
          ..sort((a, b) {
            final scoreA = _getFacultyScore(a, date);
            final scoreB = _getFacultyScore(b, date);
            return scoreA.compareTo(scoreB);
          });

        // Assign faculty to halls
        for (final hallId in sessionHalls) {
          // Find the best available faculty
          final availableFacultyForHall = sortedFaculty.where((f) {
            // Check if faculty is not already assigned to another hall in this session
            return !_hallFacultyMap.values.contains(f['faculty_id']);
          }).toList();

          if (availableFacultyForHall.isNotEmpty) {
            _hallFacultyMap[hallId] =
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
                        'Assigned: ${_hallFacultyMap.length} / $_requiredFaculty halls',
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
                    itemCount: widget.selectedHalls.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final hallId = widget.selectedHalls[index];
                      final assignedFacultyId = _hallFacultyMap[hallId];
                      final assignedFaculty = assignedFacultyId != null
                          ? _faculty.firstWhere(
                              (f) => f['faculty_id'] == assignedFacultyId)
                          : null;

                      return Card(
                        child: ListTile(
                          title: Text('Hall: $hallId'),
                          subtitle: assignedFaculty != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Faculty: ${assignedFaculty['faculty_name']}'),
                                    Text(
                                        'Department: ${assignedFaculty['dept_id']}'),
                                  ],
                                )
                              : const Text('No faculty assigned'),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (facultyId) {
                              setState(() {
                                if (assignedFacultyId != null) {
                                  _hallFacultyMap.remove(hallId);
                                }
                                if (facultyId.isNotEmpty) {
                                  _hallFacultyMap[hallId] = facultyId;
                                }
                              });
                            },
                            itemBuilder: (context) => [
                              if (assignedFacultyId != null)
                                const PopupMenuItem(
                                  value: '',
                                  child: Text('Remove Assignment'),
                                ),
                              ...filteredFaculty
                                  .where((f) => !_hallFacultyMap.values
                                      .contains(f['faculty_id']))
                                  .map(
                                    (faculty) => PopupMenuItem(
                                      value: faculty['faculty_id'],
                                      child: Text(
                                          '${faculty['faculty_name']} (${faculty['dept_id']})'),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Preview Seating'),
                    onPressed: _hallFacultyMap.length != _requiredFaculty
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PreviewSeatingPage(
                                  exams: widget.exams,
                                  selectedStudents: widget.selectedStudents,
                                  selectedHalls: widget.selectedHalls,
                                  hallFacultyMap: _hallFacultyMap,
                                ),
                              ),
                            );
                          },
                  ),
                ),
              ],
            ),
    );
  }
}
