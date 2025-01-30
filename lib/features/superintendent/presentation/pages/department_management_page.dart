import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'student_management_page.dart';
import 'faculty_management_page.dart';
import 'course_management_page.dart';

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

      final departmentsResponse =
          await Supabase.instance.client.from('departments').select('''
            *,
            courses:course(course_code),
            students:student(student_reg_no),
            faculty:faculty(faculty_id)
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

  void _showDepartmentInfo(Map<String, dynamic> department) {
    final courses = (department['courses'] ?? []) as List;
    final students = (department['students'] ?? []) as List;
    final faculty = (department['faculty'] ?? []) as List;
    final createdAt = DateTime.parse(department['created_at']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(24),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    department['dept_name'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.pop(context);
                    _addEditDepartment(department: department);
                  },
                  tooltip: 'Edit Department',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange,
                    ),
                  ),
                  child: Text(
                    department['dept_id'],
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Created ${_formatDate(createdAt)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Statistics Row
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      icon: Icons.people,
                      value: students.length.toString(),
                      label: 'Students',
                    ),
                    VerticalDivider(color: Colors.grey[300], width: 32),
                    _buildStatColumn(
                      icon: Icons.school,
                      value: faculty.length.toString(),
                      label: 'Faculty',
                    ),
                    VerticalDivider(color: Colors.grey[300], width: 32),
                    _buildStatColumn(
                      icon: Icons.book,
                      value: courses.length.toString(),
                      label: 'Courses',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Navigation Cards
            _buildInfoCard(
              icon: Icons.people,
              title: 'Manage Students',
              count: students.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StudentManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.school,
              title: 'Manage Faculty',
              count: faculty.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FacultyManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.book,
              title: 'Manage Courses',
              count: courses.length,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CourseManagementPage(
                      initialDepartment: department['dept_id'],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Colors.grey[700]),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} years ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.grey[700]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$count ${title.toLowerCase()}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = (screenWidth / 280).floor();

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Showing ${filteredDepartments.length} departments',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredDepartments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.business_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No departments found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 1.2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filteredDepartments.length,
                        itemBuilder: (context, index) {
                          final department = filteredDepartments[index];
                          final courses = department['courses'] as List;
                          final students = department['students'] as List;
                          final faculty = department['faculty'] as List;
                          final courseCount = courses.length;
                          final studentCount = students.length;
                          final facultyCount = faculty.length;

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.orange.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _showDepartmentInfo(department),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
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
                                                department['dept_name'],
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.orange,
                                                  ),
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
                                        ),
                                        PopupMenuButton(
                                          icon: const Icon(Icons.more_vert),
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            if (courseCount == 0 &&
                                                studentCount == 0)
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _addEditDepartment(
                                                  department: department);
                                            } else if (value == 'delete') {
                                              _deleteDepartment(
                                                  department['dept_id']);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildStatItem(
                                          icon: Icons.book,
                                          value: courseCount.toString(),
                                          label: 'Courses',
                                        ),
                                        _buildStatItem(
                                          icon: Icons.school,
                                          value: facultyCount.toString(),
                                          label: 'Faculty',
                                        ),
                                        _buildStatItem(
                                          icon: Icons.people,
                                          value: studentCount.toString(),
                                          label: 'Students',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
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
