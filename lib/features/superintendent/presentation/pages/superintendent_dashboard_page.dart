import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_management_page.dart';
import 'course_management_page.dart';
import 'department_management_page.dart';
import 'package:office_pal/features/superintendent/presentation/pages/faculty_management_page.dart';
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
  Map<String, int> stats = {
    'students': 0,
    'courses': 0,
    'departments': 0,
    'faculty': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => isLoading = true);
    try {
      final studentsCount = await Supabase.instance.client
          .from('student')
          .select('*', const FetchOptions(count: CountOption.exact));
      final coursesCount = await Supabase.instance.client
          .from('course')
          .select('*', const FetchOptions(count: CountOption.exact));
      final departmentsCount = await Supabase.instance.client
          .from('departments')
          .select('*', const FetchOptions(count: CountOption.exact));
      final facultyCount = await Supabase.instance.client
          .from('faculty')
          .select('*', const FetchOptions(count: CountOption.exact));

      if (mounted) {
        setState(() {
          stats = {
            'students': studentsCount.count ?? 0,
            'courses': coursesCount.count ?? 0,
            'departments': departmentsCount.count ?? 0,
            'faculty': facultyCount.count ?? 0,
          };
          isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Error loading stats: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(response);
          isLoading = false;
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
        setState(() => isLoading = false);
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
      _loadNotifications();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $error'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
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
              onRefresh: () async {
                await Future.wait([
                  _loadNotifications(),
                  _loadStats(),
                ]);
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Stats',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StatsGrid(isSmallScreen: isSmallScreen),
                    const SizedBox(height: 32),
                    const Divider(height: 1),
                    const SizedBox(height: 32),
                    const Text(
                      'Management Tools',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GridView.count(
                      crossAxisCount: isSmallScreen ? 1 : 3,
                      shrinkWrap: true,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: isSmallScreen ? 2.5 : 1.2,
                      children: [
                        _DashboardCard(
                          title: 'Student Management',
                          icon: Icons.people,
                          description:
                              'Manage student records and course registrations',
                          color: Colors.blue,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const StudentManagementPage(),
                            ),
                          ),
                        ),
                        _DashboardCard(
                          title: 'Course Management',
                          icon: Icons.book,
                          description:
                              'Manage courses, credits, and departments',
                          color: Colors.green,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const CourseManagementPage(),
                            ),
                          ),
                        ),
                        _DashboardCard(
                          title: 'Department Management',
                          icon: Icons.business,
                          description:
                              'Manage departments and faculty assignments',
                          color: Colors.orange,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const DepartmentManagementPage(),
                            ),
                          ),
                        ),
                        _DashboardCard(
                          title: 'Faculty Management',
                          icon: Icons.people_outline,
                          description:
                              'Manage faculty members and their status',
                          color: Colors.purple,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const FacultyManagementPage(),
                            ),
                          ),
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
                                              onPressed: () {
                                                _updateNotificationStatus(
                                                    notification, 'approved');
                                                Navigator.pop(context);
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel_outlined,
                                                color: Colors.red,
                                              ),
                                              onPressed: () {
                                                _updateNotificationStatus(
                                                    notification, 'declined');
                                                Navigator.pop(context);
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
  final IconData icon;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.8),
                color,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
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

class _StatsGrid extends ConsumerStatefulWidget {
  final bool isSmallScreen;

  const _StatsGrid({required this.isSmallScreen});

  @override
  ConsumerState<_StatsGrid> createState() => _StatsGridState();
}

class _StatsGridState extends ConsumerState<_StatsGrid> {
  bool isLoading = true;
  Map<String, int> stats = {
    'students': 0,
    'courses': 0,
    'departments': 0,
    'faculty': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final studentsCount = await Supabase.instance.client
          .from('student')
          .select('*', const FetchOptions(count: CountOption.exact));
      final coursesCount = await Supabase.instance.client
          .from('course')
          .select('*', const FetchOptions(count: CountOption.exact));
      final departmentsCount = await Supabase.instance.client
          .from('departments')
          .select('*', const FetchOptions(count: CountOption.exact));
      final facultyCount = await Supabase.instance.client
          .from('faculty')
          .select('*', const FetchOptions(count: CountOption.exact));

      if (mounted) {
        setState(() {
          stats = {
            'students': studentsCount.count ?? 0,
            'courses': coursesCount.count ?? 0,
            'departments': departmentsCount.count ?? 0,
            'faculty': facultyCount.count ?? 0,
          };
          isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Error loading stats: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: widget.isSmallScreen ? 2 : 4,
      shrinkWrap: true,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: widget.isSmallScreen ? 1.5 : 1.8,
      children: [
        _StatCard(
          title: 'Total Students',
          value: stats['students'] ?? 0,
          icon: Icons.people,
          color: Colors.blue,
          isLoading: isLoading,
        ),
        _StatCard(
          title: 'Total Courses',
          value: stats['courses'] ?? 0,
          icon: Icons.book,
          color: Colors.green,
          isLoading: isLoading,
        ),
        _StatCard(
          title: 'Departments',
          value: stats['departments'] ?? 0,
          icon: Icons.business,
          color: Colors.orange,
          isLoading: isLoading,
        ),
        _StatCard(
          title: 'Faculty Members',
          value: stats['faculty'] ?? 0,
          icon: Icons.people_outline,
          color: Colors.purple,
          isLoading: isLoading,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            if (isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
