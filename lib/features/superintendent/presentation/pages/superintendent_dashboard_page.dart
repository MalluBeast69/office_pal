import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/core/utils/screen_utils.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'faculty_management_page.dart';
import 'student_management_page.dart';
import 'course_management_page.dart';
import 'department_management_page.dart';
import 'hall_management_page.dart';
import 'exam_management_page.dart';
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
    extends ConsumerState<SuperintendentDashboardPage>
    with TickerProviderStateMixin {
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

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Hover states for menu items
  Map<String, bool> _isHovering = {
    'dashboard': false,
    'students': false,
    'courses': false,
    'departments': false,
    'faculty': false,
    'halls': false,
    'exams': false,
    'seating': false,
    'logout': false,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 600) {
        showScreenSizeWarning(context);
      }
    });

    // Initialize animations
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start animations
    _fadeInController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _slideController.dispose();
    super.dispose();
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Delete Notification',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this notification?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(),
            ),
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

      // Sign out from Supabase
      await Supabase.instance.client.auth.signOut();

      if (context.mounted) {
        // Force navigation to login and clear all routes
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
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
    final theme = Theme.of(context);
    final isWeb = kIsWeb;

    return Scaffold(
      body: isLoading
          ? _buildLoadingScreen()
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (!isSmallScreen) _buildSidebar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        child: CustomScrollView(
                          slivers: [
                            SliverAppBar(
                              pinned: true,
                              floating: true,
                              automaticallyImplyLeading: isSmallScreen,
                              title: isSmallScreen
                                  ? Text(
                                      'Superintendent Dashboard',
                                      style: GoogleFonts.poppins(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                              backgroundColor: isWeb
                                  ? Colors.white.withOpacity(0.8)
                                  : theme.scaffoldBackgroundColor,
                              actions: [
                                _buildNotificationButton(),
                                const SizedBox(width: 8),
                                _buildProfileButton(),
                                const SizedBox(width: 16),
                              ],
                              elevation: 0,
                            ),
                            SliverFadeTransition(
                              opacity: _fadeInAnimation,
                              sliver: SliverToBoxAdapter(
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: _buildDashboardContent(
                                      isSmallScreen, theme),
                                ),
                              ),
                            ),
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

  Widget _buildLoadingScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade100,
            Colors.blue.shade50,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.blue,
              size: 50,
            ),
            const SizedBox(height: 24),
            Text(
              'Office Pal',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading Dashboard...',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Office Pal',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildSidebarItem('dashboard', 'Dashboard', Icons.dashboard),
                  _buildSidebarItem('students', 'Students', Icons.people),
                  _buildSidebarItem('courses', 'Courses', Icons.book),
                  _buildSidebarItem(
                      'departments', 'Departments', Icons.business),
                  _buildSidebarItem('faculty', 'Faculty', Icons.school),
                  _buildSidebarItem('halls', 'Halls', Icons.meeting_room),
                  _buildSidebarItem('exams', 'Exams', Icons.assignment),
                  _buildSidebarItem('seating', 'Seating', Icons.event_seat),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.grey.shade200),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovering['logout'] = true),
                onExit: (_) => setState(() => _isHovering['logout'] = false),
                child: ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: _isHovering['logout'] ?? false
                        ? Colors.red
                        : Colors.grey.shade600,
                  ),
                  title: Text(
                    'Logout',
                    style: GoogleFonts.poppins(
                      color: _isHovering['logout'] ?? false
                          ? Colors.red
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => _signOut(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(String id, String title, IconData icon) {
    final isSelected = _currentSection == id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering[id] = true),
        onExit: (_) => setState(() => _isHovering[id] = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.shade50
                : _isHovering[id] ?? false
                    ? Colors.grey.shade100
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Icon(
              icon,
              color: isSelected
                  ? Colors.blue.shade700
                  : _isHovering[id] ?? false
                      ? Colors.blue.shade700
                      : Colors.grey.shade600,
            ),
            title: Text(
              title,
              style: GoogleFonts.poppins(
                color: isSelected
                    ? Colors.blue.shade700
                    : _isHovering[id] ?? false
                        ? Colors.blue.shade700
                        : Colors.grey.shade800,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            onTap: () {
              if (id == 'dashboard') {
                setState(() => _currentSection = id);
              } else {
                _navigateToManagement(id);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    final pendingCount =
        notifications.where((n) => n['status'] == 'pending').length;

    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          splashRadius: 24,
          onPressed: () => _showNotificationsDialog(),
        ),
        if (pendingCount > 0)
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
                pendingCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileButton() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          // Show profile options or logout
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.shade100,
                child: Icon(
                  Icons.person,
                  size: 20,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Superintendent',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardContent(bool isSmallScreen, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeSection(theme),
          const SizedBox(height: 32),
          _buildStatsGrid(isSmallScreen),
          const SizedBox(height: 32),
          _buildRecentActivity(isSmallScreen),
          const SizedBox(height: 32),
          _buildTasksSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection(ThemeData theme) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, Superintendent',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Here\'s what\'s happening with your examination management today',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _navigateToManagement('exams'),
                        icon: const Icon(Icons.add),
                        label: const Text('New Exam'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          backgroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () => _navigateToManagement('seating'),
                        icon: const Icon(Icons.event_seat),
                        label: const Text('Manage Seating'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (MediaQuery.of(context).size.width >= 900)
              Container(
                width: 240,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Icon(
                    Icons.school,
                    size: 80,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Statistics',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCircularStat('Students', stats['students'],
                        Icons.people, Colors.blue.shade700),
                    _buildCircularStat('Faculty', stats['faculty'],
                        Icons.school, Colors.purple.shade700),
                    if (!isSmallScreen)
                      _buildCircularStat('Courses', stats['courses'],
                          Icons.book, Colors.green.shade700),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (isSmallScreen)
                      _buildCircularStat('Courses', stats['courses'],
                          Icons.book, Colors.green.shade700),
                    _buildCircularStat('Departments', stats['departments'],
                        Icons.business, Colors.orange.shade700),
                    _buildCircularStat('Halls', stats['halls'],
                        Icons.meeting_room, Colors.teal.shade700),
                    if (!isSmallScreen)
                      _buildCircularStat('Exams', stats['exams'],
                          Icons.assignment, Colors.red.shade700),
                  ],
                ),
                if (isSmallScreen)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: _buildCircularStat('Exams', stats['exams'],
                        Icons.assignment, Colors.red.shade700),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircularStat(
      String title, int count, IconData icon, Color color) {
    // Calculate a percentage for the circle based on the count
    // Just for visual effect, not meant to be precise
    final double percentage = count > 0 ? (count / 100.0).clamp(0.1, 1.0) : 0.1;

    return InkWell(
      onTap: () => _navigateToManagement(title.toLowerCase()),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 80,
                  width: 80,
                  child: CircularProgressIndicator(
                    value: percentage,
                    strokeWidth: 8,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Container(
                  height: 60,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.1),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: color,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              count.toString(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(bool isSmallScreen) {
    final pendingNotifications =
        notifications.where((n) => n['status'] == 'pending').take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Notifications',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () => _showNotificationsDialog(),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: pendingNotifications.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No pending notifications',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pendingNotifications.length,
                  separatorBuilder: (context, index) => Divider(
                    color: Colors.grey.shade200,
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final notification = pendingNotifications[index];
                    return _buildNotificationItem(notification);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    IconData icon;
    Color color;

    switch (notification['type']) {
      case 'leave_request':
        icon = Icons.event_busy;
        color = Colors.orange;
        break;
      case 'exam_update':
        icon = Icons.assignment;
        color = Colors.blue;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.grey;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        notification['title'] ?? 'Notification',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        notification['message'] ?? '',
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            splashRadius: 24,
            onPressed: () =>
                _updateNotificationStatus(notification, 'approved'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            splashRadius: 24,
            onPressed: () =>
                _updateNotificationStatus(notification, 'declined'),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksSection() {
    // This is a placeholder for future task management functionality
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Tasks',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.task_alt,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No upcoming tasks',
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600,
            maxHeight: 600,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: notifications.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No notifications',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: notifications.length,
                          separatorBuilder: (context, index) => Divider(
                            color: Colors.grey.shade200,
                          ),
                          itemBuilder: (context, index) {
                            final notification = notifications[index];
                            return _buildNotificationItem(notification);
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

// Add this widget for SliverFadeTransition
class SliverFadeTransition extends StatelessWidget {
  final Animation<double> opacity;
  final Widget sliver;

  const SliverFadeTransition({
    Key? key,
    required this.opacity,
    required this.sliver,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedOpacity(
      opacity: opacity.value,
      duration: const Duration(milliseconds: 0),
      sliver: sliver,
    );
  }
}
