import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_management_page.dart';
import 'course_management_page.dart';
import 'department_management_page.dart';
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
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select('*', const FetchOptions(count: CountOption.exact))
          .eq('status', 'pending');

      setState(() {
        _notificationCount = response.count ?? 0;
      });
    } catch (e) {
      developer.log('Error loading notification count: $e');
    }
  }

  void _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _showNotifications() async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => NotificationsDialog(
            notifications: List<Map<String, dynamic>>.from(response),
            onStatusChanged: () {
              _loadNotificationCount();
            },
          ),
        );
      }
    } catch (e) {
      developer.log('Error loading notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load notifications'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                onPressed: _showNotifications,
              ),
              if (_notificationCount > 0)
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
                      _notificationCount.toString(),
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
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                      builder: (context) => const StudentManagementPage(),
                    ),
                  ),
                ),
                _DashboardCard(
                  title: 'Course Management',
                  icon: Icons.book,
                  description: 'Manage courses, credits, and departments',
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CourseManagementPage(),
                    ),
                  ),
                ),
                _DashboardCard(
                  title: 'Department Management',
                  icon: Icons.business,
                  description: 'Manage departments and faculty assignments',
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DepartmentManagementPage(),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
    'registrations': 0,
  };

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
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
      final registrationsCount = await Supabase.instance.client
          .from('registered_students')
          .select('*', const FetchOptions(count: CountOption.exact));

      if (mounted) {
        setState(() {
          stats = {
            'students': studentsCount.count ?? 0,
            'courses': coursesCount.count ?? 0,
            'departments': departmentsCount.count ?? 0,
            'registrations': registrationsCount.count ?? 0,
          };
          isLoading = false;
        });
      }
    } catch (e) {
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
          title: 'Course Registrations',
          value: stats['registrations'] ?? 0,
          icon: Icons.assignment,
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

class NotificationsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onStatusChanged;

  const NotificationsDialog({
    super.key,
    required this.notifications,
    required this.onStatusChanged,
  });

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  Future<void> _updateNotificationStatus(
      String notificationId, String status) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'status': status}).eq('id', notificationId);

      if (status == 'approved') {
        // Update faculty availability
        final notification = widget.notifications
            .firstWhere((n) => n['id'].toString() == notificationId);
        if (notification['type'] == 'leave_request') {
          await Supabase.instance.client
              .from('faculty')
              .update({'is_available': false}).eq(
                  'faculty_id', notification['from_faculty_id']);
        }
      }

      widget.onStatusChanged();
    } catch (e) {
      developer.log('Error updating notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update notification'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
              child: widget.notifications.isEmpty
                  ? const Center(
                      child: Text('No notifications'),
                    )
                  : ListView.builder(
                      itemCount: widget.notifications.length,
                      itemBuilder: (context, index) {
                        final notification = widget.notifications[index];
                        final metadata =
                            jsonDecode(notification['metadata'] ?? '{}');
                        final isPending = notification['status'] == 'pending';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            title: Text(notification['title']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notification['message']),
                                if (metadata != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'From: ${metadata['faculty_name']} (${metadata['department']})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                      'Duration: ${DateTime.parse(metadata['from_date']).toString().split(' ')[0]} to ${DateTime.parse(metadata['to_date']).toString().split(' ')[0]}'),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  'Status: ${notification['status'].toUpperCase()}',
                                  style: TextStyle(
                                    color: notification['status'] == 'pending'
                                        ? Colors.orange
                                        : notification['status'] == 'approved'
                                            ? Colors.green
                                            : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            trailing: isPending
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check,
                                            color: Colors.green),
                                        onPressed: () =>
                                            _updateNotificationStatus(
                                                notification['id'].toString(),
                                                'approved'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.red),
                                        onPressed: () =>
                                            _updateNotificationStatus(
                                                notification['id'].toString(),
                                                'rejected'),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
