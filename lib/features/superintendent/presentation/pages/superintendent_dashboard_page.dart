import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/core/utils/screen_utils.dart';
import 'faculty_management_page.dart';
import 'student_management_page.dart';
import 'course_management_page.dart';
import 'department_management_page.dart';
import 'hall_management_page.dart';
import 'exam_management_page.dart';
import 'seating_arrangement/select_exam_page.dart';
import 'seating_management_page.dart';
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
    'exams': 0,
    'seating': 0,
  };
  String _currentSection = 'dashboard';

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 600) {
        showScreenSizeWarning(context);
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load statistics
      final studentResponse =
          await Supabase.instance.client.from('student').select();

      final courseResponse =
          await Supabase.instance.client.from('course').select();

      final departmentResponse =
          await Supabase.instance.client.from('departments').select();

      final facultyResponse =
          await Supabase.instance.client.from('faculty').select();

      final hallResponse = await Supabase.instance.client.from('hall').select();

      final examResponse = await Supabase.instance.client.from('exam').select();

      // Load notifications
      final notificationsResponse = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          stats = {
            'students': studentResponse.length,
            'courses': courseResponse.length,
            'departments': departmentResponse.length,
            'faculty': facultyResponse.length,
            'halls': hallResponse.length,
            'exams': examResponse.length,
            'seating': 0,
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
        ).then((_) => _loadData());
        break;
      case 'courses':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CourseManagementPage(),
          ),
        ).then((_) => _loadData());
        break;
      case 'departments':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DepartmentManagementPage(),
          ),
        ).then((_) => _loadData());
        break;
      case 'faculty':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const FacultyManagementPage(),
          ),
        ).then((_) => _loadData());
        break;
      case 'halls':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HallManagementPage(),
          ),
        ).then((_) => _loadData());
        break;
      case 'exams':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ExamManagementPage(),
          ),
        ).then((_) => _loadData());
        break;
      case 'seating':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SeatingManagementPage(),
            settings:
                const RouteSettings(name: SeatingManagementPage.routeName),
          ),
        ).then((_) => _loadData());
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

  Future<void> _signOut(BuildContext context) async {
    try {
      setState(() => isLoading = true);
      // Clear any stored session/auth data
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.refreshSession();

      if (context.mounted) {
        // Force navigation to login and clear all routes
        await Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
        // Additional cleanup
        setState(() {
          _currentSection = 'dashboard';
          notifications.clear();
          stats.clear();
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: const Text('Superintendent Dashboard'),
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            )
          : null,
      body: Row(
        children: [
          if (!isSmallScreen) _buildSidebar(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12.0 : 24.0,
                        vertical: isSmallScreen ? 12.0 : 24.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Bar with Notifications
                          if (!isSmallScreen)
                            Align(
                              alignment: Alignment.topRight,
                              child: Stack(
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
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          notifications
                                              .where((n) =>
                                                  n['status'] == 'pending')
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
                            ),
                          // Welcome Section with Quick Stats
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Welcome, Superintendent',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Here\'s your overview for today',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _buildQuickStatCard(
                                      'Students',
                                      stats['students'],
                                      Icons.people,
                                      Colors.blue,
                                    ),
                                    _buildQuickStatCard(
                                      'Courses',
                                      stats['courses'],
                                      Icons.book,
                                      Colors.green,
                                    ),
                                    _buildQuickStatCard(
                                      'Departments',
                                      stats['departments'],
                                      Icons.business,
                                      Colors.orange,
                                    ),
                                    _buildQuickStatCard(
                                      'Faculty',
                                      stats['faculty'],
                                      Icons.school,
                                      Colors.purple,
                                    ),
                                    _buildQuickStatCard(
                                      'Halls',
                                      stats['halls'],
                                      Icons.meeting_room,
                                      Colors.teal,
                                    ),
                                    _buildQuickStatCard(
                                      'Exams',
                                      stats['exams'],
                                      Icons.assignment,
                                      Colors.pink,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Recent Activity Section
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.history,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Recent Activity',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        // Recent Activity List
                                        ...notifications
                                            .take(5)
                                            .map((notification) => ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor: notification[
                                                                'status'] ==
                                                            'pending'
                                                        ? Colors.orange
                                                            .withOpacity(0.2)
                                                        : notification[
                                                                    'status'] ==
                                                                'approved'
                                                            ? Colors.green
                                                                .withOpacity(
                                                                    0.2)
                                                            : Colors.red
                                                                .withOpacity(
                                                                    0.2),
                                                    child: Icon(
                                                      notification['type'] ==
                                                              'leave_request'
                                                          ? Icons.event_busy
                                                          : Icons.notifications,
                                                      color: notification[
                                                                  'status'] ==
                                                              'pending'
                                                          ? Colors.orange
                                                          : notification[
                                                                      'status'] ==
                                                                  'approved'
                                                              ? Colors.green
                                                              : Colors.red,
                                                    ),
                                                  ),
                                                  title: Text(
                                                      notification['title'] ??
                                                          ''),
                                                  subtitle: Text(
                                                    notification['message'] ??
                                                        '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  trailing: Text(
                                                    notification['status']
                                                            ?.toUpperCase() ??
                                                        'PENDING',
                                                    style: TextStyle(
                                                      color: notification[
                                                                  'status'] ==
                                                              'pending'
                                                          ? Colors.orange
                                                          : notification[
                                                                      'status'] ==
                                                                  'approved'
                                                              ? Colors.green
                                                              : Colors.red,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                )),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (!isSmallScreen) const SizedBox(width: 24),
                              if (!isSmallScreen)
                                Expanded(
                                  child: Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Upcoming Events',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          // Upcoming Events List
                                          _buildUpcomingEvent(
                                            'Next Exam',
                                            'Mathematics Final',
                                            'Tomorrow, 9:00 AM',
                                            Icons.assignment,
                                            Colors.blue,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildUpcomingEvent(
                                            'Faculty Meeting',
                                            'Department Heads',
                                            'Friday, 2:00 PM',
                                            Icons.groups,
                                            Colors.purple,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildUpcomingEvent(
                                            'Results Due',
                                            'First Semester',
                                            'Next Week',
                                            Icons.assessment,
                                            Colors.orange,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      drawer: isSmallScreen
          ? Drawer(
              child: _buildSidebar(),
            )
          : null,
    );
  }

  Widget _buildSidebar() {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'superintendent@example.com';
    final name =
        email.split('@')[0].split('.').map((s) => s.capitalize()).join(' ');

    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.primary,
      child: Column(
        children: [
          // Profile Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Theme.of(context).colorScheme.primary,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Text(
                    name.substring(0, 2).toUpperCase(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Superintendent',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          // Navigation Section
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _buildNavItem(
                    'Dashboard',
                    Icons.dashboard,
                    'dashboard',
                  ),
                  _buildNavItem(
                    'Students',
                    Icons.people,
                    'students',
                  ),
                  _buildNavItem(
                    'Courses',
                    Icons.book,
                    'courses',
                  ),
                  _buildNavItem(
                    'Departments',
                    Icons.business,
                    'departments',
                  ),
                  _buildNavItem(
                    'Faculty',
                    Icons.school,
                    'faculty',
                  ),
                  _buildNavItem(
                    'Halls',
                    Icons.meeting_room,
                    'halls',
                  ),
                  _buildNavItem(
                    'Exams',
                    Icons.assignment,
                    'exams',
                  ),
                  _buildNavItem(
                    'Seating',
                    Icons.event_seat,
                    'seating',
                  ),
                  // Notifications
                  Stack(
                    children: [
                      _buildNavItem(
                        'Notifications',
                        Icons.notifications,
                        'notifications',
                      ),
                      if (notifications
                          .where((n) => n['status'] == 'pending')
                          .isNotEmpty)
                        Positioned(
                          right: 24,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              notifications
                                  .where((n) => n['status'] == 'pending')
                                  .length
                                  .toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Logout Button
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Card(
              elevation: 0,
              color:
                  Theme.of(context).colorScheme.errorContainer.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: () => _signOut(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, String section) {
    final isSelected = _currentSection == section;
    final color =
        isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;

    return ListTile(
      onTap: () {
        setState(() => _currentSection = section);
        if (section == 'notifications') {
          _showNotificationsDialog();
        } else if (section != 'dashboard') {
          _navigateToManagement(section);
        }
      },
      selected: isSelected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildQuickStatCard(
      String title, int value, IconData icon, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEvent(
    String title,
    String subtitle,
    String time,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
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

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
