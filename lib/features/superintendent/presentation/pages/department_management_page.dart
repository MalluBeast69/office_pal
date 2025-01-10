import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class DepartmentManagementPage extends ConsumerStatefulWidget {
  const DepartmentManagementPage({super.key});

  @override
  ConsumerState<DepartmentManagementPage> createState() =>
      _DepartmentManagementPageState();
}

class _DepartmentManagementPageState
    extends ConsumerState<DepartmentManagementPage> {
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> filteredDepartments = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadDepartments();
  }

  Future<void> loadDepartments() async {
    try {
      developer.log('Loading departments...');

      // Load departments with course and student counts
      final departmentsResponse =
          await Supabase.instance.client.from('departments').select('''
            dept_id,
            dept_name,
            created_at,
            updated_at,
            courses:course!dept_id(course_code),
            students:student!dept_id(student_reg_no)
          ''').order('dept_id');

      developer.log('Loaded ${departmentsResponse.length} departments');

      setState(() {
        departments = List<Map<String, dynamic>>.from(departmentsResponse);
        filterDepartments();
        isLoading = false;
      });
    } catch (error) {
      developer.log('Error loading departments: $error', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load departments: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => isLoading = false);
    }
  }

  void filterDepartments() {
    setState(() {
      filteredDepartments = departments.where((department) {
        return searchQuery.isEmpty ||
            department['dept_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            department['dept_id']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());
      }).toList();
    });
  }

  Future<void> _addEditDepartment({Map<String, dynamic>? department}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => DepartmentDialog(department: department),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        if (department == null) {
          // Add new department
          await Supabase.instance.client.from('departments').insert(result);
        } else {
          // Update existing department
          await Supabase.instance.client
              .from('departments')
              .update(result)
              .eq('dept_id', department['dept_id']);
        }
        loadDepartments();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                department == null
                    ? 'Failed to add department'
                    : 'Failed to update department',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteDepartment(String deptId) async {
    // First check if department has any courses or students
    try {
      final coursesCount = await Supabase.instance.client
          .from('course')
          .select('course_code')
          .eq('dept_id', deptId);

      final studentsCount = await Supabase.instance.client
          .from('student')
          .select('student_reg_no')
          .eq('dept_id', deptId);

      if (coursesCount.isNotEmpty || studentsCount.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Cannot delete department that has courses or students assigned'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Delete'),
          content:
              const Text('Are you sure you want to delete this department?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        setState(() => isLoading = true);
        await Supabase.instance.client
            .from('departments')
            .delete()
            .eq('dept_id', deptId);
        loadDepartments();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete department'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Department Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Department',
            onPressed: () => _addEditDepartment(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by department name or ID',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                searchQuery = value;
                filterDepartments();
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredDepartments.isEmpty
                    ? const Center(
                        child: Text(
                          'No departments found',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredDepartments.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final department = filteredDepartments[index];
                          final courses = department['courses'] as List;
                          final students = department['students'] as List;
                          final courseCount = courses.length;
                          final studentCount = students.length;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(department['dept_name']),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orange),
                                    ),
                                    child: Text(
                                      department['dept_id'],
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Courses: $courseCount\n'
                                'Students: $studentCount',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit Department',
                                    onPressed: () => _addEditDepartment(
                                        department: department),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    tooltip: 'Delete Department',
                                    onPressed:
                                        courseCount > 0 || studentCount > 0
                                            ? null
                                            : () => _deleteDepartment(
                                                department['dept_id']),
                                  ),
                                ],
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

class DepartmentDialog extends StatefulWidget {
  final Map<String, dynamic>? department;

  const DepartmentDialog({
    super.key,
    this.department,
  });

  @override
  State<DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<DepartmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.department != null) {
      _idController.text = widget.department!['dept_id'];
      _nameController.text = widget.department!['dept_name'];
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.department != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Department' : 'Add Department'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _idController,
              decoration: const InputDecoration(labelText: 'Department ID'),
              enabled: !isEditing,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter department ID';
                }
                if (!RegExp(r'^[A-Z]{4}$').hasMatch(value.toUpperCase())) {
                  return 'Invalid format (e.g., DPCS)';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Department Name'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter department name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'dept_id': _idController.text.trim().toUpperCase(),
                'dept_name': _nameController.text.trim(),
              });
            }
          },
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
