import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'select_halls_page.dart';

class SelectStudentsPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;

  const SelectStudentsPage({super.key, required this.exams});

  @override
  ConsumerState<SelectStudentsPage> createState() => _SelectStudentsPageState();
}

class _SelectStudentsPageState extends ConsumerState<SelectStudentsPage> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showRegularOnly = false;
  Set<String> _selectedStudents = {};

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      setState(() => _isLoading = true);

      // Get course IDs from selected exams
      final courseIds = widget.exams.map((e) => e['course_id']).toSet();

      final response = await Supabase.instance.client
          .from('registered_students')
          .select()
          .in_('course_code', courseIds.toList());

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading students: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _filterStudents() {
    return _students.where((student) {
      // Search filter
      final regNo = student['student_reg_no']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      if (!regNo.contains(searchLower)) {
        return false;
      }

      // Regular/Supplementary filter
      if (_showRegularOnly && !student['is_reguler']) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _filterStudents();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Students'),
        actions: [
          TextButton.icon(
            icon: Icon(
              filteredStudents.every((student) =>
                      _selectedStudents.contains(student['student_reg_no']))
                  ? Icons.deselect
                  : Icons.select_all,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              filteredStudents.every((student) =>
                      _selectedStudents.contains(student['student_reg_no']))
                  ? 'Deselect All'
                  : 'Select All',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            onPressed: () {
              setState(() {
                if (filteredStudents.every((student) =>
                    _selectedStudents.contains(student['student_reg_no']))) {
                  _selectedStudents.clear();
                } else {
                  _selectedStudents.addAll(filteredStudents
                      .map((s) => s['student_reg_no'] as String));
                }
              });
            },
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
                    hintText: 'Search by registration number',
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
                SwitchListTile(
                  title: const Text('Show Regular Students Only'),
                  value: _showRegularOnly,
                  onChanged: (value) =>
                      setState(() => _showRegularOnly = value),
                  dense: true,
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
                    itemCount: filteredStudents.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final student = filteredStudents[index];
                      final regNo = student['student_reg_no'];
                      final isSelected = _selectedStudents.contains(regNo);

                      return Card(
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedStudents.add(regNo);
                              } else {
                                _selectedStudents.remove(regNo);
                              }
                            });
                          },
                          title: Text(regNo),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Type: ${student['is_reguler'] ? 'Regular' : 'Supplementary'}',
                              ),
                              Text('Course: ${student['course_code']}'),
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
                          'Selected: ${_selectedStudents.length} students',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                        onPressed: _selectedStudents.isEmpty
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SelectHallsPage(
                                      exams: widget.exams,
                                      selectedStudents:
                                          _selectedStudents.toList(),
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
