import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'faculty_management_page.dart';
import 'student_management_page.dart';
import 'course_management_page.dart';
import 'department_management_page.dart';
import 'hall_management_page.dart';
import 'exam_management_page.dart';
import 'dart:convert';
import 'dart:developer' as developer;

class SuperintendentDashboardPage extends ConsumerStatefulWidget {
  const SuperintendentDashboardPage({super.key});

  @override
  ConsumerState<SuperintendentDashboardPage> createState() =>
      _SuperintendentDashboardPageState();
}

class _SuperintendentDashboardPageState
    extends ConsumerState<SuperintendentDashboardPage> {
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = false;
  Map<String, dynamic> stats = {
    'students': 0,
    'courses': 0,
    'departments': 0,
    'faculty': 0,
    'halls': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load statistics
      final studentCount =
          await Supabase.instance.client.from('student').select().count();

      final courseCount =
          await Supabase.instance.client.from('course').select().count();

      final departmentCount =
          await Supabase.instance.client.from('departments').select().count();

      final facultyCount =
          await Supabase.instance.client.from('faculty').select().count();

      final hallCount =
          await Supabase.instance.client.from('hall').select().count();

      final examCount =
          await Supabase.instance.client.from('exam').select().count();

      // Load notifications
      final notificationsResponse = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          stats = {
            'students': studentCount ?? 0,
            'courses': courseCount ?? 0,
            'departments': departmentCount ?? 0,
            'faculty': facultyCount ?? 0,
            'halls': hallCount ?? 0,
            'exams': examCount ?? 0,
          };
          notifications =
              List<Map<String, dynamic>>.from(notificationsResponse);
          isLoading = false;
        });
      }
    } catch (error) {
      developer.log('Error loading data: $error');
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

  void _navigateToManagement(String type) {
    switch (type) {
      case 'students':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const StudentManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
      case 'courses':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CourseManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
      case 'departments':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DepartmentManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
      case 'faculty':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FacultyManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
      case 'halls':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HallManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
      case 'exams':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ExamManagementPage(),
          ),
        ).then((_) => _loadData()); // Reload data when returning
        break;
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading notifications: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateNotificationStatus(
      Map<String, dynamic> notification, String status) async {
    setState(() => isLoading = true);
    try {
      // Update notification status
      await Supabase.instance.client
          .from('notifications')
          .update({'status': status}).eq('id', notification['id']);

      // If this is a leave request and it's being approved/declined,
      // update faculty availability
      if (notification['type'] == 'leave_request') {
        final metadata = jsonDecode(notification['metadata']);
        if (status == 'approved') {
          await Supabase.instance.client
              .from('faculty')
              .update({'is_available': false}).eq(
                  'faculty_id', notification['from_faculty_id']);
        }
      }

      // Reload all data
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request ${status.toUpperCase()}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Delete',
              textColor: Colors.white,
              onPressed: () => _showDeleteConfirmation(notification),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _deleteNotification(Map<String, dynamic> notification) async {
    setState(() => isLoading = true);
    try {
      await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('id', notification['id']);

      // Update the local state immediately
      setState(() {
        notifications.removeWhere((n) => n['id'] == notification['id']);
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting notification: $error'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  Future<bool> _showDeleteConfirmation(
      Map<String, dynamic> notification) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notification'),
        content:
            const Text('Are you sure you want to delete this notification?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteNotification(notification);
    }
    return result ?? false;
  }

  void _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Widget _buildStatCard(String title, int value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Superintendent Dashboard'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () => _showNotificationsDialog(),
              ),
              if (notifications
                  .where((n) => n['status'] == 'pending')
                  .isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      notifications
                          .where((n) => n['status'] == 'pending')
                          .length
                          .toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
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
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12.0 : 16.0,
                  vertical: isSmallScreen ? 12.0 : 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        'Quick Stats',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 20 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSmallScreen)
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.2,
                        children: [
                          _DashboardCard(
                            title: 'Students',
                            value: stats['students'].toString(),
                            icon: Icons.people,
                            color: Colors.blue,
                            onTap: () => _navigateToManagement('students'),
                          ),
                          _DashboardCard(
                            title: 'Courses',
                            value: stats['courses'].toString(),
                            icon: Icons.book,
                            color: Colors.green,
                            onTap: () => _navigateToManagement('courses'),
                          ),
                          _DashboardCard(
                            title: 'Departments',
                            value: stats['departments'].toString(),
                            icon: Icons.business,
                            color: Colors.orange,
                            onTap: () => _navigateToManagement('departments'),
                          ),
                          _DashboardCard(
                            title: 'Faculty',
                            value: stats['faculty'].toString(),
                            icon: Icons.school,
                            color: Colors.purple,
                            onTap: () => _navigateToManagement('faculty'),
                          ),
                          _DashboardCard(
                            title: 'Halls',
                            value: stats['halls'].toString(),
                            icon: Icons.meeting_room,
                            color: Colors.teal,
                            onTap: () => _navigateToManagement('halls'),
                          ),
                          _DashboardCard(
                            title: 'Exams',
                            value: stats['exams'].toString(),
                            icon: Icons.assignment,
                            color: Colors.pink,
                            onTap: () => _navigateToManagement('exams'),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DashboardCard(
                            title: 'Total Students',
                            value: stats['students'].toString(),
                            icon: Icons.people,
                            color: Colors.blue,
                            onTap: () => _navigateToManagement('students'),
                          ),
                          _DashboardCard(
                            title: 'Total Courses',
                            value: stats['courses'].toString(),
                            icon: Icons.book,
                            color: Colors.green,
                            onTap: () => _navigateToManagement('courses'),
                          ),
                          _DashboardCard(
                            title: 'Departments',
                            value: stats['departments'].toString(),
                            icon: Icons.business,
                            color: Colors.orange,
                            onTap: () => _navigateToManagement('departments'),
                          ),
                          _DashboardCard(
                            title: 'Faculty Members',
                            value: stats['faculty'].toString(),
                            icon: Icons.school,
                            color: Colors.purple,
                            onTap: () => _navigateToManagement('faculty'),
                          ),
                          _DashboardCard(
                            title: 'Halls',
                            value: stats['halls'].toString(),
                            icon: Icons.meeting_room,
                            color: Colors.teal,
                            onTap: () => _navigateToManagement('halls'),
                          ),
                          _DashboardCard(
                            title: 'Exams',
                            value: stats['exams'].toString(),
                            icon: Icons.assignment,
                            color: Colors.pink,
                            onTap: () => _navigateToManagement('exams'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        'Management Tools',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 20 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSmallScreen)
                      ListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _ManagementCard(
                            title: 'Student Management',
                            description:
                                'Manage student records and registrations',
                            icon: Icons.people,
                            color: Colors.blue,
                            onTap: () => _navigateToManagement('students'),
                          ),
                          _ManagementCard(
                            title: 'Course Management',
                            description: 'Manage courses and credits',
                            icon: Icons.book,
                            color: Colors.green,
                            onTap: () => _navigateToManagement('courses'),
                          ),
                          _ManagementCard(
                            title: 'Department Management',
                            description: 'Manage departments and assignments',
                            icon: Icons.business,
                            color: Colors.orange,
                            onTap: () => _navigateToManagement('departments'),
                          ),
                          _ManagementCard(
                            title: 'Faculty Management',
                            description: 'Manage faculty and availability',
                            icon: Icons.school,
                            color: Colors.purple,
                            onTap: () => _navigateToManagement('faculty'),
                          ),
                          _ManagementCard(
                            title: 'Hall Management',
                            description:
                                'Manage halls, seating arrangements and availability',
                            icon: Icons.meeting_room,
                            color: Colors.teal,
                            onTap: () => _navigateToManagement('halls'),
                          ),
                          _ManagementCard(
                            title: 'Exam Management',
                            description: 'Manage exams and schedules',
                            icon: Icons.assignment,
                            color: Colors.pink,
                            onTap: () => _navigateToManagement('exams'),
                          ),
                        ]
                            .map((card) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: card,
                                ))
                            .toList(),
                      )
                    else
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        children: [
                          _ManagementCard(
                            title: 'Student Management',
                            description:
                                'Manage student records and course registrations',
                            icon: Icons.people,
                            color: Colors.blue,
                            onTap: () => _navigateToManagement('students'),
                          ),
                          _ManagementCard(
                            title: 'Course Management',
                            description:
                                'Manage courses, credits, and departments',
                            icon: Icons.book,
                            color: Colors.green,
                            onTap: () => _navigateToManagement('courses'),
                          ),
                          _ManagementCard(
                            title: 'Department Management',
                            description:
                                'Manage departments and faculty assignments',
                            icon: Icons.business,
                            color: Colors.orange,
                            onTap: () => _navigateToManagement('departments'),
                          ),
                          _ManagementCard(
                            title: 'Faculty Management',
                            description:
                                'Manage faculty members and their availability',
                            icon: Icons.school,
                            color: Colors.purple,
                            onTap: () => _navigateToManagement('faculty'),
                          ),
                          _ManagementCard(
                            title: 'Hall Management',
                            description:
                                'Manage halls, seating arrangements and availability',
                            icon: Icons.meeting_room,
                            color: Colors.teal,
                            onTap: () => _navigateToManagement('halls'),
                          ),
                          _ManagementCard(
                            title: 'Exam Management',
                            description: 'Manage exams and schedules',
                            icon: Icons.assignment,
                            color: Colors.pink,
                            onTap: () => _navigateToManagement('exams'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: 600,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: notifications.isEmpty
                      ? const Center(
                          child: Text('No notifications'),
                        )
                      : ListView.builder(
                          itemCount: notifications.length,
                          itemBuilder: (context, index) {
                            final notification = notifications[index];
                            final metadata =
                                jsonDecode(notification['metadata'] ?? '{}');
                            return Dismissible(
                              key: Key(notification['id'].toString()),
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16.0),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                final result =
                                    await _showDeleteConfirmation(notification);
                                if (result && mounted) {
                                  setState(() {}); // Refresh the dialog's UI
                                }
                                return result;
                              },
                              child: Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  title: Text(notification['title'] ?? ''),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(notification['message'] ?? ''),
                                      if (notification['type'] ==
                                              'leave_request' &&
                                          metadata != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8.0),
                                          child: Text(
                                            'From: ${metadata['from_date'] ?? 'N/A'} To: ${metadata['to_date'] ?? 'N/A'}',
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: notification['status'] ==
                                                  'pending'
                                              ? Colors.orange.withOpacity(0.1)
                                              : notification['status'] ==
                                                      'approved'
                                                  ? Colors.green
                                                      .withOpacity(0.1)
                                                  : Colors.red.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: notification['status'] ==
                                                    'pending'
                                                ? Colors.orange
                                                : notification['status'] ==
                                                        'approved'
                                                    ? Colors.green
                                                    : Colors.red,
                                          ),
                                        ),
                                        child: Text(
                                          (notification['status'] ?? 'pending')
                                              .toUpperCase(),
                                          style: TextStyle(
                                            color: notification['status'] ==
                                                    'pending'
                                                ? Colors.orange
                                                : notification['status'] ==
                                                        'approved'
                                                    ? Colors.green
                                                    : Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: notification['status'] == 'pending'
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.green,
                                              ),
                                              onPressed: () async {
                                                await _updateNotificationStatus(
                                                    notification, 'approved');
                                                if (mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel_outlined,
                                                color: Colors.red,
                                              ),
                                              onPressed: () async {
                                                await _updateNotificationStatus(
                                                    notification, 'declined');
                                                if (mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                            ),
                                          ],
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            final result =
                                                await _showDeleteConfirmation(
                                                    notification);
                                            if (result && mounted) {
                                              setState(
                                                  () {}); // Refresh the dialog's UI
                                            }
                                          },
                                        ),
                                  isThreeLine: true,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: isSmallScreen ? double.infinity : 200,
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.1),
                Colors.white,
              ],
            ),
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: isSmallScreen ? 24 : 28),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 28 : 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ManagementCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (isSmallScreen) {
      return Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
