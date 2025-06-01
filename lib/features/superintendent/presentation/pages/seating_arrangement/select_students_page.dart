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
  final Set<String> _selectedStudents = {};

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

      // Load registered students with student details
      final response =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            is_reguler,
            course_code,
            student:student_reg_no (
              student_name,
              dept_id,
              semester
            )
          ''').in_('course_code', courseIds.toList());

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
      final studentName =
          student['student']?['student_name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      if (!regNo.contains(searchLower) && !studentName.contains(searchLower)) {
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
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: filteredStudents.every((student) =>
                        _selectedStudents.contains(student['student_reg_no']))
                    ? Theme.of(context).colorScheme.error.withOpacity(0.9)
                    : Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: filteredStudents.every((student) =>
                        _selectedStudents.contains(student['student_reg_no']))
                    ? Theme.of(context).colorScheme.onError
                    : Theme.of(context).colorScheme.onPrimaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              icon: Icon(
                filteredStudents.every((student) =>
                        _selectedStudents.contains(student['student_reg_no']))
                    ? Icons.deselect
                    : Icons.select_all,
                size: 20,
              ),
              label: Text(
                filteredStudents.every((student) =>
                        _selectedStudents.contains(student['student_reg_no']))
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
                    hintText: 'Search by name or registration number',
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
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Hint card
                        Card(
                          margin: const EdgeInsets.all(16.0),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Selected Exams',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.exams.map((exam) {
                                    return Chip(
                                      label: Text(
                                        '${exam['course_id']} (${exam['session']})',
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Showing only students registered for these exams',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Add debug info card
                        Card(
                          margin: const EdgeInsets.all(16.0),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.bug_report,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Debug Info',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Total Selected Students: ${_selectedStudents.length}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  'Maximum Students per Session: ${_students.where((s) => s['is_reguler']).length}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Student list
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 600 ? 5 : 4,
                            childAspectRatio: 1.8,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                          itemCount: filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = filteredStudents[index];
                            final regNo = student['student_reg_no'];
                            final studentDetails =
                                student['student'] as Map<String, dynamic>;
                            final isSelected =
                                _selectedStudents.contains(regNo);

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
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
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedStudents.remove(regNo);
                                    } else {
                                      _selectedStudents.add(regNo);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  studentDetails[
                                                      'student_name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  regNo,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontSize: 9,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: Checkbox(
                                              value: isSelected,
                                              onChanged: (value) {
                                                setState(() {
                                                  if (value == true) {
                                                    _selectedStudents
                                                        .add(regNo);
                                                  } else {
                                                    _selectedStudents
                                                        .remove(regNo);
                                                  }
                                                });
                                              },
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: student['is_reguler']
                                                  ? Colors.green
                                                      .withOpacity(0.1)
                                                  : Colors.orange
                                                      .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: student['is_reguler']
                                                    ? Colors.green
                                                        .withOpacity(0.2)
                                                    : Colors.orange
                                                        .withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              student['is_reguler'] ? 'R' : 'S',
                                              style: TextStyle(
                                                color: student['is_reguler']
                                                    ? Colors.green
                                                    : Colors.orange,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              student['course_code'],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontSize: 9,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${studentDetails['dept_id']} - ${studentDetails['semester']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontSize: 9,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Fixed bottom action bar
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
                ),
              ],
            ),
    );
  }
}
