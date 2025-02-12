import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:office_pal/features/auth/presentation/pages/login_page.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:table_calendar/table_calendar.dart';

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
  List<Map<String, dynamic>> assignedExams = [];
  List<Map<String, dynamic>> leaveRequests = [];
  final _scrollController = ScrollController();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load assigned exams from seating_arr table with exam details
      final examsResponse = await Supabase.instance.client
          .from('seating_arr')
          .select('''
            *,
            exam!inner(
              exam_date,
              session,
              time
            ),
            hall:hall_id(*)
          ''')
          .eq('faculty_id', widget.facultyId)
          .order('created_at', ascending: false);

      // Load leave requests separately
      final requestsResponse = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('from_faculty_id', widget.facultyId)
          .eq('type', 'leave_request')
          .order('created_at', ascending: false);

      developer.log('Raw response length: ${examsResponse.length}');

      if (mounted) {
        // Create a map to store unique assignments by date and hall
        final Map<String, Map<String, dynamic>> uniqueExams = {};

        // Sort assignments by date to get the most recent ones first
        final sortedAssignments = List<Map<String, dynamic>>.from(examsResponse)
          ..sort((a, b) {
            final dateA = DateTime.parse(a['exam']['exam_date']);
            final dateB = DateTime.parse(b['exam']['exam_date']);
            return dateB.compareTo(dateA);
          });

        // Keep only the most recent assignment for each hall
        for (var assignment in sortedAssignments) {
          if (assignment['exam'] == null ||
              assignment['hall'] == null ||
              assignment['exam']['exam_date'] == null ||
              assignment['hall']['hall_id'] == null) {
            continue; // Skip invalid assignments
          }

          final examDate = DateTime.parse(assignment['exam']['exam_date']);
          final hallId = assignment['hall']['hall_id'];
          final key = hallId;

          // Only add if we don't have this hall yet or if this is a more recent assignment
          if (!uniqueExams.containsKey(key) ||
              DateTime.parse(uniqueExams[key]!['exam']['exam_date'])
                  .isBefore(examDate)) {
            uniqueExams[key] = assignment;
          }
        }

        final finalList = uniqueExams.values.toList();
        developer.log('Final unique halls count: ${finalList.length}');

        setState(() {
          assignedExams = finalList;
          leaveRequests = List<Map<String, dynamic>>.from(requestsResponse);
          isLoading = false;
          _organizeEvents();
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

  void _organizeEvents() {
    _events = {};
    for (var exam in assignedExams) {
      final examDate = DateTime.parse(exam['exam']['exam_date']);
      final dateKey = DateTime(examDate.year, examDate.month, examDate.day);
      if (_events[dateKey] == null) {
        _events[dateKey] = [];
      }
      _events[dateKey]!.add(exam);
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Map<String, dynamic>? _getNextDuty() {
    final now = DateTime.now();
    Map<String, dynamic>? nextDuty;
    DateTime? nextDutyDate;

    for (var exam in assignedExams) {
      final examDate = DateTime.parse(exam['exam']['exam_date']);
      if (examDate.isAfter(now)) {
        if (nextDutyDate == null || examDate.isBefore(nextDutyDate)) {
          nextDutyDate = examDate;
          nextDuty = exam;
        }
      }
    }

    return nextDuty;
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

  void _signOut() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your details...',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ).animate().fadeIn(),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Details updated'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                color: Theme.of(context).primaryColor,
                backgroundColor: Colors.white,
                strokeWidth: 3,
                displacement: 40,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // App Bar
                    SliverAppBar(
                      expandedHeight: 200,
                      floating: true,
                      pinned: true,
                      stretch: true,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withOpacity(0.8),
                              ],
                            ),
                          ),
                          child: SafeArea(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.white,
                                  child: Text(
                                    widget.facultyName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ).animate().scale(),
                                const SizedBox(height: 8),
                                Text(
                                  widget.facultyName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.3,
                                      curve: Curves.easeOutQuad,
                                    ),
                                Text(
                                  widget.facultyId,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.3,
                                      curve: Curves.easeOutQuad,
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: _signOut,
                        ),
                      ],
                    ),
                    // Faculty Info
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // Next Duty Card
                            if (_getNextDuty() != null) ...[
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).primaryColor,
                                      Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Card(
                                  elevation: 0,
                                  color: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.upcoming,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Next Duty',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(color: Colors.white24),
                                        Builder(builder: (context) {
                                          final nextDuty = _getNextDuty()!;
                                          final examDate = DateTime.parse(
                                              nextDuty['exam']['exam_date']);
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.meeting_room,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Hall ${nextDuty['hall']['hall_id']}',
                                                    style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.calendar_today,
                                                    color: Colors.white70,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    DateFormat('EEEE, MMMM d')
                                                        .format(examDate),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.access_time,
                                                    color: Colors.white70,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${nextDuty['exam']['time']} (${nextDuty['exam']['session']})',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                              ).animate().fadeIn().slideY().then().shimmer(
                                    duration: const Duration(seconds: 2),
                                    color: Colors.white24,
                                  ),
                              const SizedBox(height: 16),
                            ],
                            // Calendar Card
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_month,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Duty Calendar',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(),
                                    TableCalendar(
                                      firstDay: DateTime.now()
                                          .subtract(const Duration(days: 365)),
                                      lastDay: DateTime.now()
                                          .add(const Duration(days: 365)),
                                      focusedDay: _focusedDay,
                                      calendarFormat: _calendarFormat,
                                      selectedDayPredicate: (day) =>
                                          isSameDay(_selectedDay, day),
                                      eventLoader: _getEventsForDay,
                                      onDaySelected: (selectedDay, focusedDay) {
                                        setState(() {
                                          _selectedDay = selectedDay;
                                          _focusedDay = focusedDay;
                                        });
                                      },
                                      onFormatChanged: (format) {
                                        setState(() {
                                          _calendarFormat = format;
                                        });
                                      },
                                      onPageChanged: (focusedDay) {
                                        _focusedDay = focusedDay;
                                      },
                                      calendarStyle: CalendarStyle(
                                        markersMaxCount: 1,
                                        markerSize: 8,
                                        markerDecoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                        ),
                                        selectedDecoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .primaryColor
                                              .withOpacity(0.8),
                                          shape: BoxShape.circle,
                                        ),
                                        todayDecoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .primaryColor
                                              .withOpacity(0.4),
                                          shape: BoxShape.circle,
                                        ),
                                        markerMargin:
                                            const EdgeInsets.only(top: 4),
                                      ),
                                    ),
                                    if (_selectedDay != null &&
                                        _getEventsForDay(_selectedDay!)
                                            .isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 8.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children:
                                              _getEventsForDay(_selectedDay!)
                                                  .map((event) => ListTile(
                                                        leading: const Icon(
                                                            Icons.meeting_room),
                                                        title: Text(
                                                            'Hall: ${event['hall']['hall_id']}'),
                                                        subtitle: Text(
                                                            '${event['exam']['time']} (${event['exam']['session']})'),
                                                      ))
                                                  .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn().slideY(),
                          ],
                        ),
                      ),
                    ),
                    // Leave Request Button
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: FilledButton.icon(
                          onPressed: _requestLeave,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Request Leave'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 24),
                          ),
                        ).animate().fadeIn().slideX(),
                      ),
                    ),
                    // Leave Requests
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.history,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Leave History',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ).animate().fadeIn(),
                            const SizedBox(height: 16),
                            if (leaveRequests.isEmpty)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          color: Colors.grey[600]),
                                      const SizedBox(width: 8),
                                      const Text('No leave requests yet'),
                                    ],
                                  ),
                                ),
                              ).animate().fadeIn()
                            else
                              ...leaveRequests.map((request) {
                                if (request['metadata'] == null)
                                  return const SizedBox.shrink();

                                final metadata =
                                    jsonDecode(request['metadata'] ?? '{}');
                                if (metadata == null)
                                  return const SizedBox.shrink();

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(request['title']),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(request['message']),
                                        const SizedBox(height: 4),
                                        Text(
                                          'From: ${metadata['from_date']} To: ${metadata['to_date']}',
                                          style: const TextStyle(fontSize: 12),
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
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.2,
                                      delay: Duration(
                                          milliseconds:
                                              leaveRequests.indexOf(request) *
                                                  100),
                                    );
                              }).toList(),
                          ],
                        ),
                      ),
                    ),
                    // Assigned Exams
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.event_seat,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Assigned Halls',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ).animate().fadeIn(),
                            const SizedBox(height: 16),
                            if (assignedExams.isEmpty)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          color: Colors.grey[600]),
                                      const SizedBox(width: 8),
                                      const Text('No halls assigned yet'),
                                    ],
                                  ),
                                ),
                              ).animate().fadeIn()
                            else
                              ...assignedExams.map((assignment) {
                                final exam = assignment['exam'];
                                final hall = assignment['hall'];
                                if (exam == null || hall == null)
                                  return const SizedBox.shrink();

                                final examDate = DateTime.parse(
                                    exam['exam_date'] ??
                                        DateTime.now().toString());
                                final isToday = DateTime.now()
                                        .difference(examDate)
                                        .inDays ==
                                    0;
                                final isPast = DateTime.now().isAfter(examDate);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: isPast
                                      ? Colors.grey[100]
                                      : isToday
                                          ? Colors.green[50]
                                          : Colors.white,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Theme.of(context)
                                                  .primaryColor
                                                  .withOpacity(0.1),
                                              child: Icon(
                                                Icons.meeting_room,
                                                size: 18,
                                                color: Theme.of(context)
                                                    .primaryColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Hall ${hall['hall_id'] ?? ''}',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            if (isToday)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green[100],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: Colors.green),
                                                ),
                                                child: const Text(
                                                  'TODAY',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.calendar_today,
                                                    size: 14,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  DateFormat('EEE, MMM d')
                                                      .format(examDate),
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.access_time,
                                                    size: 14,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  exam['time'] ?? '',
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.wb_sunny,
                                                    size: 14,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  exam['session'] ?? '',
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.2,
                                      delay: Duration(
                                          milliseconds: assignedExams
                                                  .indexOf(assignment) *
                                              100),
                                    );
                              }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
