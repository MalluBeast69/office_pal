import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/presentation/pages/exam_creator_page.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/providers/holiday_provider.dart';
import 'package:office_pal/features/controller/domain/services/holiday_service.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:office_pal/features/controller/presentation/pages/exam_management_page.dart';
import 'package:office_pal/core/utils/screen_utils.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';

class ExamDateDialog extends StatelessWidget {
  final DateTime selectedDate;
  final List<Map<String, dynamic>> exams;

  const ExamDateDialog({
    super.key,
    required this.selectedDate,
    required this.exams,
  });

  @override
  Widget build(BuildContext context) {
    final dateExams = exams.where((exam) {
      final examDate = DateTime.parse(exam['exam_date']);
      return examDate.year == selectedDate.year &&
          examDate.month == selectedDate.month &&
          examDate.day == selectedDate.day;
    }).toList();

    return AlertDialog(
      title: Text('Exams on ${DateFormat('MMM d, y').format(selectedDate)}'),
      content: SizedBox(
        width: double.maxFinite,
        child: dateExams.isEmpty
            ? const Center(
                child: Text('No exams scheduled for this date'),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: dateExams.map((exam) {
                    final course = exam['course'] as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        title: Text(course['course_code'] as String),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(course['course_name'] as String),
                            Text(
                              '${exam['session']} - ${exam['time']} (${exam['duration']} mins)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (exam['new_date'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Postponed to: ${DateFormat('MMM d, y').format(DateTime.parse(exam['new_date']))}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    if (exam['postponement_note'] != null)
                                      Text(
                                        'Reason: ${exam['postponement_note']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class ControllerDashboardPage extends ConsumerStatefulWidget {
  const ControllerDashboardPage({super.key});

  @override
  ConsumerState<ControllerDashboardPage> createState() =>
      _ControllerDashboardPageState();
}

class _ControllerDashboardPageState
    extends ConsumerState<ControllerDashboardPage>
    with TickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showCalendar = true;
  String _currentSection = 'dashboard';
  bool isLoading = false;

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Hover states for menu items
  Map<String, bool> _isHovering = {
    'dashboard': false,
    'create_exams': false,
    'manage_exams': false,
    'import_schedule': false,
    'calendar': false,
    'logout': false,
  };

  @override
  void initState() {
    super.initState();
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

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error signing out'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<dynamic> _getEventsForDay(
      DateTime day, List<Map<String, dynamic>> exams, List<Holiday> holidays) {
    final events = <dynamic>[];

    // Add exams
    events.addAll(exams.where((exam) {
      final examDate = DateTime.parse(exam['exam_date']);
      return examDate.year == day.year &&
          examDate.month == day.month &&
          examDate.day == day.day;
    }));

    // Add holidays
    events.addAll(holidays.where((holiday) =>
        holiday.date.year == day.year &&
        holiday.date.month == day.month &&
        holiday.date.day == day.day));

    return events;
  }

  void _showEventDialog(BuildContext context, DateTime selectedDay,
      List<Map<String, dynamic>> exams, List<Holiday> holidays) {
    final events = _getEventsForDay(selectedDay, exams, holidays);
    if (events.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(DateFormat('MMM d, y').format(selectedDay)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...events.map((event) {
                if (event is Map<String, dynamic>) {
                  final course = event['course'] as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(course['course_code'] as String),
                    subtitle: Text('${event['session']} - ${event['time']}'),
                  );
                } else if (event is Holiday) {
                  return ListTile(
                    leading: const Icon(Icons.celebration, color: Colors.red),
                    title: Text(event.name),
                    subtitle: Text(event.type),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.8),
                color.withOpacity(0.6),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                  _buildSidebarItem(
                      'create_exams', 'Create Exams', Icons.add_circle_outline),
                  _buildSidebarItem(
                      'manage_exams', 'Manage Exams', Icons.edit_calendar),
                  _buildSidebarItem(
                      'import_schedule', 'Import Schedule', Icons.upload_file),
                  _buildSidebarItem(
                      'calendar', 'Calendar View', Icons.calendar_month),
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
              child: _buildLogoutButton(),
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
                _navigateToSection(id);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Card(
      elevation: 0,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: () => _signOut(context),
        leading: Icon(
          Icons.logout,
          color: Colors.red.shade700,
        ),
        title: Text(
          'Logout',
          style: GoogleFonts.poppins(
            color: Colors.red.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _navigateToSection(String id) {
    switch (id) {
      case 'create_exams':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ExamCreatorPage()),
        );
        break;
      case 'manage_exams':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ExamManagementPage()),
        );
        break;
      case 'import_schedule':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ExamManagementPage()),
        );
        break;
      case 'calendar':
        setState(() => _showCalendar = !_showCalendar);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider);
    final holidaysAsync = ref.watch(holidaysProvider(_focusedDay.year));
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isWeb = kIsWeb;

    return Scaffold(
      drawer: isSmallScreen
          ? Drawer(
              child: _buildSidebar(),
            )
          : null,
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
                        onRefresh: () async {
                          ref.refresh(examsProvider);
                          ref.refresh(holidaysProvider(_focusedDay.year));
                        },
                        child: CustomScrollView(
                          slivers: [
                            SliverAppBar(
                              pinned: true,
                              floating: true,
                              automaticallyImplyLeading: isSmallScreen,
                              title: isSmallScreen
                                  ? Text(
                                      'Controller Dashboard',
                                      style: GoogleFonts.poppins(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                              backgroundColor: isWeb
                                  ? Colors.white.withOpacity(0.8)
                                  : Theme.of(context).scaffoldBackgroundColor,
                              actions: [
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
                                      isSmallScreen, Theme.of(context)),
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

  Widget _buildProfileButton() {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'controller@example.com';
    final name =
        email.split('@')[0].split('.').map((s) => s.capitalize()).join(' ');

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
                'Controller',
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
          _buildExamCalendar(isSmallScreen),
          const SizedBox(height: 32),
          _buildUpcomingExams(isSmallScreen),
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
                    'Welcome back, Controller',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage your examination schedules and arrangements',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _navigateToSection('create_exams'),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Exam'),
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
                        onPressed: () => _navigateToSection('manage_exams'),
                        icon: const Icon(Icons.edit_calendar),
                        label: const Text('Manage Exams'),
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

  Widget _buildExamCalendar(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exam Calendar',
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
            child: Consumer(
              builder: (context, ref, child) {
                final examsAsync = ref.watch(examsProvider);
                final holidaysAsync =
                    ref.watch(holidaysProvider(_focusedDay.year));

                return examsAsync.when(
                  data: (exams) => holidaysAsync.when(
                    data: (holidays) => TableCalendar(
                      firstDay:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      calendarFormat: _calendarFormat,
                      onFormatChanged: (format) =>
                          setState(() => _calendarFormat = format),
                      eventLoader: (day) =>
                          _getEventsForDay(day, exams, holidays),
                      calendarStyle: CalendarStyle(
                        markerSize: 8,
                        markerDecoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                        ),
                        markersMaxCount: 3,
                        markerMargin:
                            const EdgeInsets.symmetric(horizontal: 0.5),
                        holidayTextStyle: const TextStyle(color: Colors.red),
                        holidayDecoration: const BoxDecoration(),
                        selectedDecoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        _showEventDialog(context, selectedDay, exams, holidays);
                      },
                      headerStyle: HeaderStyle(
                        titleTextStyle: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        formatButtonTextStyle: GoogleFonts.poppins(),
                        formatButtonDecoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        Center(child: Text('Error loading holidays: $error')),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Error loading exams: $error')),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingExams(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Exams',
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
            child: Consumer(
              builder: (context, ref, child) {
                final examsAsync = ref.watch(examsProvider);

                return examsAsync.when(
                  data: (exams) {
                    final now = DateTime.now();
                    final upcomingExams = exams.where((exam) {
                      final examDate = DateTime.parse(exam['exam_date']);
                      return examDate.isAfter(now);
                    }).toList()
                      ..sort((a, b) => DateTime.parse(a['exam_date'])
                          .compareTo(DateTime.parse(b['exam_date'])));

                    if (upcomingExams.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No upcoming exams',
                              style: GoogleFonts.poppins(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: upcomingExams.take(5).map((exam) {
                        final course = exam['course'] as Map<String, dynamic>;
                        final examDate = DateTime.parse(exam['exam_date']);
                        final daysUntil = examDate.difference(now).inDays;

                        Color statusColor;
                        if (daysUntil <= 3) {
                          statusColor = Colors.red;
                        } else if (daysUntil <= 7) {
                          statusColor = Colors.orange;
                        } else {
                          statusColor = Colors.blue;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.school,
                                      color: statusColor, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${course['course_code']} - ${course['course_name']}',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      color: statusColor.withOpacity(0.8),
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('MMM d, y').format(examDate),
                                    style: GoogleFonts.poppins(
                                      color: statusColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(Icons.access_time,
                                      color: statusColor.withOpacity(0.8),
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${exam['session']} - ${exam['time']}',
                                    style: GoogleFonts.poppins(
                                      color: statusColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                daysUntil == 0
                                    ? 'Today'
                                    : daysUntil == 1
                                        ? 'Tomorrow'
                                        : '$daysUntil days remaining',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Error loading exams: $error')),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

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
