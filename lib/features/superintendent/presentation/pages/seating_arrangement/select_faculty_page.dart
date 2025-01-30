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
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, String> _hallFacultyMap = {};
  int _requiredFaculty = 0;

  @override
  void initState() {
    super.initState();
    _requiredFaculty = widget.selectedHalls.length;
    _loadFaculty();
  }

  Future<void> _loadFaculty() async {
    try {
      setState(() => _isLoading = true);
      final response = await Supabase.instance.client
          .from('faculty')
          .select()
          .eq('is_available', true);

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

  void _assignAvailableFaculty() {
    final availableFaculty = _filterFaculty()
      ..sort((a, b) => a['faculty_name'].toString().compareTo(b['faculty_name']
          .toString())); // Sort by name for consistent assignment

    _hallFacultyMap.clear();

    // Assign faculty to halls
    for (int i = 0; i < widget.selectedHalls.length; i++) {
      if (i < availableFaculty.length) {
        _hallFacultyMap[widget.selectedHalls[i]] =
            availableFaculty[i]['faculty_id'];
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaculty = _filterFaculty();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Faculty'),
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.select_all,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              'Assign Available',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            onPressed: _assignAvailableFaculty,
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
