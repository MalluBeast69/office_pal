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
    developer.log('Starting leave request process');

    developer.log('Showing leave request dialog');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LeaveRequestDialog(
        facultyName: widget.facultyName,
        departmentId: widget.departmentId,
      ),
    );

    developer.log('Dialog result: $result');
    if (result != null) {
      setState(() => isLoading = true);
      try {
        developer.log('Submitting leave request to Supabase');
        final response =
            await Supabase.instance.client.from('notifications').insert({
          'type': 'leave_request',
          'from_faculty_id': widget.facultyId,
          'title': 'Leave Request from ${widget.facultyName}',
          'message': result['reason'],
          'status': 'pending',
          'metadata': jsonEncode({
            'faculty_name': widget.facultyName,
            'department': widget.departmentId,
            'from_date': result['fromDate'],
            'to_date': result['toDate'],
            'reason': result['reason'],
          }),
        }).select();
        developer.log('Leave request submitted successfully: $response');

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
        developer.log('Error submitting leave request: $error',
            error: error, stackTrace: StackTrace.current);
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
    developer.log('Navigating to login page');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Welcome, ${widget.facultyName}',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
          ),
        ),
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
                padding: EdgeInsets.all(isSmallScreen ? 8.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Faculty Information Card
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Faculty Information',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 18 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              children: [
                                Text('ID: ${widget.facultyId}'),
                                Text('Department: ${widget.departmentId}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Courses Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Assigned Courses',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 18 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 16),
                          FilledButton.icon(
                            onPressed: _requestLeave,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              'Request Leave',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 13 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Courses List
                    if (assignedCourses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No courses assigned yet'),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: assignedCourses.map((course) {
                              return SizedBox(
                                width: constraints.maxWidth > 600
                                    ? (constraints.maxWidth / 2) - 12
                                    : constraints.maxWidth,
                                child: Card(
                                  child: ListTile(
                                    title: Text(
                                      course['course_name'],
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 15 : 16,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Code: ${course['course_code']}\n'
                                      'Credits: ${course['credit']}',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 13 : 14,
                                      ),
                                    ),
                                    isThreeLine: true,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    // Leave Requests Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Leave Requests',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Leave Requests List
                    if (leaveRequests.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No leave requests'),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: leaveRequests.map((request) {
                              final metadata = jsonDecode(request['metadata']);
                              return SizedBox(
                                width: constraints.maxWidth > 600
                                    ? (constraints.maxWidth / 2) - 12
                                    : constraints.maxWidth,
                                child: Card(
                                  child: ListTile(
                                    title: Text(
                                      request['title'],
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 15 : 16,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request['message'],
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 13 : 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'From: ${metadata['from_date']} To: ${metadata['to_date']}',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 12 : 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: request['status'] ==
                                                    'pending'
                                                ? Colors.orange.withOpacity(0.1)
                                                : request['status'] ==
                                                        'approved'
                                                    ? Colors.green
                                                        .withOpacity(0.1)
                                                    : Colors.red
                                                        .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color:
                                                  request['status'] == 'pending'
                                                      ? Colors.orange
                                                      : request['status'] ==
                                                              'approved'
                                                          ? Colors.green
                                                          : Colors.red,
                                            ),
                                          ),
                                          child: Text(
                                            request['status'].toUpperCase(),
                                            style: TextStyle(
                                              color:
                                                  request['status'] == 'pending'
                                                      ? Colors.orange
                                                      : request['status'] ==
                                                              'approved'
                                                          ? Colors.green
                                                          : Colors.red,
                                              fontSize: isSmallScreen ? 11 : 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                  ),
                                ),
                              );
                            }).toList(),
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
    // Unfocus any text field before showing date picker
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && mounted) {
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
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final dialogWidth = isSmallScreen ? screenSize.width * 0.9 : 500.0;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.8,
          maxWidth: 600,
        ),
        child: AlertDialog(
          title: Text(
            'Request Leave',
            style: TextStyle(
              fontSize: isSmallScreen ? 18 : 20,
            ),
          ),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      'From Date',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 15 : 16,
                      ),
                    ),
                    subtitle: Text(
                      _fromDate == null
                          ? 'Select date'
                          : _fromDate.toString().split(' ')[0],
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _selectDate(true),
                  ),
                  ListTile(
                    title: Text(
                      'To Date',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 15 : 16,
                      ),
                    ),
                    subtitle: Text(
                      _toDate == null
                          ? 'Select date'
                          : _toDate.toString().split(' ')[0],
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _selectDate(false),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 15,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Reason for Leave',
                      border: const OutlineInputBorder(),
                      helperText: 'Please provide at least 10 characters',
                      helperMaxLines: 2,
                      hintText:
                          'Enter a detailed reason for your leave request',
                      helperStyle: TextStyle(
                        fontSize: isSmallScreen ? 12 : 13,
                      ),
                      labelStyle: TextStyle(
                        fontSize: isSmallScreen ? 14 : 15,
                      ),
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
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                // Unfocus before validation
                FocusScope.of(context).unfocus();
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
              child: Text(
                'Submit',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
