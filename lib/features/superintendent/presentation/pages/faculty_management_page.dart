import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FacultyManagementPage extends ConsumerStatefulWidget {
  const FacultyManagementPage({super.key});

  @override
  ConsumerState<FacultyManagementPage> createState() =>
      _FacultyManagementPageState();
}

class _FacultyManagementPageState extends ConsumerState<FacultyManagementPage> {
  List<Map<String, dynamic>> facultyList = [];
  List<Map<String, dynamic>> departments = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .order('faculty_name');

      final departmentsResponse = await Supabase.instance.client
          .from('departments')
          .select()
          .order('dept_name');

      if (mounted) {
        setState(() {
          facultyList = List<Map<String, dynamic>>.from(facultyResponse);
          departments = List<Map<String, dynamic>>.from(departmentsResponse);
          isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _addFaculty() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        departments: departments,
      ),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        await Supabase.instance.client.from('faculty').insert({
          'faculty_id': result['faculty_id'],
          'faculty_name': result['faculty_name'],
          'dept_id': result['dept_id'],
          'is_available': true,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faculty added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding faculty: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _editFaculty(Map<String, dynamic> faculty) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        departments: departments,
        faculty: faculty,
      ),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        await Supabase.instance.client.from('faculty').update({
          'faculty_name': result['faculty_name'],
          'dept_id': result['dept_id'],
        }).eq('faculty_id', faculty['faculty_id']);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faculty updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating faculty: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _toggleFacultyStatus(Map<String, dynamic> faculty) async {
    setState(() => isLoading = true);
    try {
      await Supabase.instance.client
          .from('faculty')
          .update({'is_available': !faculty['is_available']}).eq(
              'faculty_id', faculty['faculty_id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            faculty['is_available']
                ? 'Faculty marked as unavailable'
                : 'Faculty marked as available',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating faculty status: $error'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Management'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Faculty List',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _addFaculty,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Faculty'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (facultyList.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No faculty members found'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: facultyList.length,
                        itemBuilder: (context, index) {
                          final faculty = facultyList[index];
                          final department = departments.firstWhere(
                            (d) => d['dept_id'] == faculty['dept_id'],
                            orElse: () => {'dept_name': 'Unknown'},
                          );
                          return Card(
                            child: ListTile(
                              title: Text(faculty['faculty_name']),
                              subtitle: Text(
                                'ID: ${faculty['faculty_id']}\n'
                                'Department: ${department['dept_name']}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editFaculty(faculty),
                                  ),
                                  Switch(
                                    value: faculty['is_available'] ?? false,
                                    onChanged: (value) =>
                                        _toggleFacultyStatus(faculty),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class FacultyDialog extends StatefulWidget {
  final List<Map<String, dynamic>> departments;
  final Map<String, dynamic>? faculty;

  const FacultyDialog({
    super.key,
    required this.departments,
    this.faculty,
  });

  @override
  State<FacultyDialog> createState() => _FacultyDialogState();
}

class _FacultyDialogState extends State<FacultyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _facultyIdController = TextEditingController();
  final _facultyNameController = TextEditingController();
  String? _selectedDepartment;

  @override
  void initState() {
    super.initState();
    if (widget.faculty != null) {
      _facultyIdController.text = widget.faculty!['faculty_id'];
      _facultyNameController.text = widget.faculty!['faculty_name'];
      _selectedDepartment = widget.faculty!['dept_id'];
    }
  }

  @override
  void dispose() {
    _facultyIdController.dispose();
    _facultyNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.faculty == null ? 'Add Faculty' : 'Edit Faculty'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.faculty == null)
                TextFormField(
                  controller: _facultyIdController,
                  decoration: const InputDecoration(
                    labelText: 'Faculty ID',
                    hintText: 'Enter faculty ID',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter faculty ID';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _facultyNameController,
                decoration: const InputDecoration(
                  labelText: 'Faculty Name',
                  hintText: 'Enter faculty name',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter faculty name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  hintText: 'Select department',
                ),
                items: widget.departments.map((department) {
                  return DropdownMenuItem<String>(
                    value: department['dept_id'] as String,
                    child: Text(department['dept_name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDepartment = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'faculty_id': _facultyIdController.text,
                'faculty_name': _facultyNameController.text,
                'dept_id': _selectedDepartment,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
