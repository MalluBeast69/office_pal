import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:office_pal/features/auth/presentation/pages/login_page.dart';

class FacultyDashboardPage extends ConsumerStatefulWidget {
  final String facultyId;
  final String facultyName;
  final String departmentId;

  const FacultyDashboardPage({
    super.key,
    required this.facultyId,
    required this.facultyName,
    required this.departmentId,
  });

  @override
  ConsumerState<FacultyDashboardPage> createState() =>
      _FacultyDashboardPageState();
}

class _FacultyDashboardPageState extends ConsumerState<FacultyDashboardPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> assignedCourses = [];
  List<Map<String, dynamic>> leaveRequests = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load assigned courses
      final coursesResponse = await Supabase.instance.client
          .from('course')
          .select()
          .eq('dept_id', widget.departmentId);

      // Load leave requests
      final requestsResponse = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('from_faculty_id', widget.facultyId)
          .eq('type', 'leave_request')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          assignedCourses = List<Map<String, dynamic>>.from(coursesResponse);
          leaveRequests = List<Map<String, dynamic>>.from(requestsResponse);
          isLoading = false;
        });
      }
    } catch (error) {
      developer.log('Error loading faculty data: $error');
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

  Future<void> _requestLeave() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => LeaveRequestDialog(
        facultyName: widget.facultyName,
        departmentId: widget.departmentId,
      ),
    );

    if (result != null) {
      setState(() => isLoading = true);
      try {
        // Get the current user session
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          throw Exception('No authenticated session found');
        }

        await Supabase.instance.client.from('notifications').insert({
          'type': 'leave_request',
          'from_faculty_id': widget.facultyId,
          'title': 'Leave Request from ${widget.facultyName}',
          'message': result['reason'],
          'status': 'pending', // Explicitly set the status
          'metadata': jsonEncode({
            // Ensure metadata is properly encoded
            'faculty_name': widget.facultyName,
            'department': widget.departmentId,
            'from_date': result['fromDate'],
            'to_date': result['toDate'],
            'reason': result['reason'],
          }),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave request submitted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (error) {
        developer.log('Error submitting leave request: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error submitting request: $error'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => isLoading = false);
        }
      }
    }
  }

  void _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
        (route) => false, // This removes all previous routes from the stack
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.facultyName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Faculty Information',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('ID: ${widget.facultyId}'),
                            Text('Department: ${widget.departmentId}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text(
                          'Assigned Courses',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _requestLeave,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Request Leave'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (assignedCourses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No courses assigned yet'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: assignedCourses.length,
                        itemBuilder: (context, index) {
                          final course = assignedCourses[index];
                          return Card(
                            child: ListTile(
                              title: Text(course['course_name']),
                              subtitle: Text(
                                'Code: ${course['course_code']}\n'
                                'Credits: ${course['credit']}',
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Leave Requests',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (leaveRequests.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No leave requests'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: leaveRequests.length,
                        itemBuilder: (context, index) {
                          final request = leaveRequests[index];
                          final metadata = jsonDecode(request['metadata']);
                          return Card(
                            child: ListTile(
                              title: Text(request['title']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(request['message']),
                                  const SizedBox(height: 4),
                                  Text(
                                    'From: ${metadata['from_date']} To: ${metadata['to_date']}',
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: request['status'] == 'pending'
                                          ? Colors.orange.withOpacity(0.1)
                                          : request['status'] == 'approved'
                                              ? Colors.green.withOpacity(0.1)
                                              : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: request['status'] == 'pending'
                                            ? Colors.orange
                                            : request['status'] == 'approved'
                                                ? Colors.green
                                                : Colors.red,
                                      ),
                                    ),
                                    child: Text(
                                      request['status'].toUpperCase(),
                                      style: TextStyle(
                                        color: request['status'] == 'pending'
                                            ? Colors.orange
                                            : request['status'] == 'approved'
                                                ? Colors.green
                                                : Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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

class LeaveRequestDialog extends StatefulWidget {
  final String facultyName;
  final String departmentId;

  const LeaveRequestDialog({
    super.key,
    required this.facultyName,
    required this.departmentId,
  });

  @override
  State<LeaveRequestDialog> createState() => _LeaveRequestDialogState();
}

class _LeaveRequestDialogState extends State<LeaveRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = _fromDate;
          }
        } else {
          _toDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Leave'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('From Date'),
                subtitle: Text(
                  _fromDate == null
                      ? 'Select date'
                      : _fromDate.toString().split(' ')[0],
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(true),
              ),
              ListTile(
                title: const Text('To Date'),
                subtitle: Text(
                  _toDate == null
                      ? 'Select date'
                      : _toDate.toString().split(' ')[0],
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(false),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for Leave',
                  border: OutlineInputBorder(),
                  helperText: 'Please provide at least 10 characters',
                  helperMaxLines: 2,
                  hintText: 'Enter a detailed reason for your leave request',
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a reason';
                  }
                  if (value.trim().length < 10) {
                    return 'Reason must be at least 10 characters long';
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
            if (_formKey.currentState!.validate() &&
                _fromDate != null &&
                _toDate != null) {
              Navigator.pop(context, {
                'fromDate': _fromDate.toString(),
                'toDate': _toDate.toString(),
                'reason': _reasonController.text.trim(),
              });
            } else if (_fromDate == null || _toDate == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select both dates'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
