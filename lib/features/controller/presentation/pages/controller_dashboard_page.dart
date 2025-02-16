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
    extends ConsumerState<ControllerDashboardPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showCalendar = true;
  String _currentSection = 'dashboard';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 600) {
        showScreenSizeWarning(context);
      }
    });
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

  Widget _buildSidebar() {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'controller@example.com';
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
                  'Controller',
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
                    'Create Exams',
                    Icons.add_circle_outline,
                    'create_exams',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ExamCreatorPage(),
                      ),
                    ),
                  ),
                  _buildNavItem(
                    'Manage Exams',
                    Icons.edit_calendar,
                    'manage_exams',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ExamManagementPage(),
                      ),
                    ),
                  ),
                  _buildNavItem(
                    'Import Schedule',
                    Icons.upload_file,
                    'import_schedule',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ExamManagementPage(),
                      ),
                    ),
                  ),
                  _buildNavItem(
                    'Calendar View',
                    Icons.calendar_month,
                    'calendar',
                    onTap: () {
                      setState(() {
                        _showCalendar = !_showCalendar;
                      });
                    },
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

  Widget _buildNavItem(String title, IconData icon, String section,
      {VoidCallback? onTap}) {
    final isSelected = _currentSection == section;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.75);

    return ListTile(
      onTap: onTap ??
          () {
            setState(() => _currentSection = section);
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
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('Building ControllerDashboardPage');
    final examsAsync = ref.watch(examsProvider);
    final holidaysAsync = ref.watch(holidaysProvider(_focusedDay.year));
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: const Text('Controller Dashboard'),
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).colorScheme.onBackground,
            )
          : null,
      drawer: isSmallScreen ? Drawer(child: _buildSidebar()) : null,
      body: Row(
        children: [
          if (!isSmallScreen) _buildSidebar(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome Section
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome, Controller',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage your exam schedules and arrangements',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Upcoming Events and Calendar Section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Calendar Section
                      if (_showCalendar)
                        Expanded(
                          flex: 2,
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: examsAsync.when(
                                data: (exams) => holidaysAsync.when(
                                  data: (holidays) => Column(
                                    children: [
                                      TableCalendar(
                                        firstDay: DateTime.now().subtract(
                                            const Duration(days: 365)),
                                        lastDay: DateTime.now()
                                            .add(const Duration(days: 365)),
                                        focusedDay: _focusedDay,
                                        selectedDayPredicate: (day) =>
                                            isSameDay(_selectedDay, day),
                                        calendarFormat: _calendarFormat,
                                        onFormatChanged: (format) => setState(
                                            () => _calendarFormat = format),
                                        eventLoader: (day) => _getEventsForDay(
                                            day, exams, holidays),
                                        calendarStyle: CalendarStyle(
                                          markerSize: 8,
                                          markerDecoration: BoxDecoration(
                                            color: Colors.blue.shade700,
                                            shape: BoxShape.circle,
                                          ),
                                          markersMaxCount: 3,
                                          markerMargin:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 0.5),
                                          holidayTextStyle: const TextStyle(
                                              color: Colors.red),
                                          holidayDecoration:
                                              const BoxDecoration(),
                                        ),
                                        holidayPredicate: (day) => holidays.any(
                                            (holiday) =>
                                                holiday.date.year == day.year &&
                                                holiday.date.month ==
                                                    day.month &&
                                                holiday.date.day == day.day),
                                        onDaySelected:
                                            (selectedDay, focusedDay) {
                                          setState(() {
                                            _selectedDay = selectedDay;
                                            _focusedDay = focusedDay;
                                          });
                                          _showEventDialog(context, selectedDay,
                                              exams, holidays);
                                        },
                                      ),
                                    ],
                                  ),
                                  loading: () => const SizedBox(
                                    height: 300,
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  ),
                                  error: (error, stack) => Center(
                                    child:
                                        Text('Error loading holidays: $error'),
                                  ),
                                ),
                                loading: () => const SizedBox(
                                  height: 300,
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                                error: (error, stack) => Center(
                                  child: Text('Error loading exams: $error'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_showCalendar) const SizedBox(width: 24),
                      // Upcoming Events Section
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.event,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Upcoming Exams',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                examsAsync.when(
                                  data: (exams) {
                                    final now = DateTime.now();
                                    final upcomingExams = exams.where((exam) {
                                      final examDate =
                                          DateTime.parse(exam['exam_date']);
                                      return examDate.isAfter(now);
                                    }).toList()
                                      ..sort((a, b) => DateTime.parse(
                                              a['exam_date'])
                                          .compareTo(
                                              DateTime.parse(b['exam_date'])));

                                    if (upcomingExams.isEmpty) {
                                      return const Center(
                                        child: Text('No upcoming exams'),
                                      );
                                    }

                                    return Column(
                                      children:
                                          upcomingExams.take(5).map((exam) {
                                        final course = exam['course']
                                            as Map<String, dynamic>;
                                        final examDate =
                                            DateTime.parse(exam['exam_date']);
                                        final daysUntil =
                                            examDate.difference(now).inDays;

                                        Color statusColor;
                                        if (daysUntil <= 3) {
                                          statusColor = Colors.red;
                                        } else if (daysUntil <= 7) {
                                          statusColor = Colors.orange;
                                        } else {
                                          statusColor = Colors.blue;
                                        }

                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color:
                                                  statusColor.withOpacity(0.2),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.school,
                                                      color: statusColor,
                                                      size: 20),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '${course['course_code']} - ${course['course_name']}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(Icons.calendar_today,
                                                      color: statusColor
                                                          .withOpacity(0.8),
                                                      size: 16),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    DateFormat('MMM d, y')
                                                        .format(examDate),
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Icon(Icons.access_time,
                                                      color: statusColor
                                                          .withOpacity(0.8),
                                                      size: 16),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${exam['session']} - ${exam['time']}',
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.w500,
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
                                                style: TextStyle(
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
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  error: (error, _) => Center(
                                    child: Text('Error loading exams: $error'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Quick Actions Grid
                  if (!_showCalendar)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 600;
                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: isDesktop ? 3 : 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: isDesktop ? 1.5 : 1.2,
                          children: [
                            _buildDashboardCard(
                              context,
                              title: 'Create Exams',
                              icon: Icons.add_circle_outline,
                              color: Colors.blue,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ExamCreatorPage(),
                                ),
                              ),
                            ),
                            _buildDashboardCard(
                              context,
                              title: 'Manage Exams',
                              icon: Icons.edit_calendar,
                              color: Colors.green,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ExamManagementPage(),
                                ),
                              ),
                            ),
                            _buildDashboardCard(
                              context,
                              title: 'Import Schedule',
                              icon: Icons.upload_file,
                              color: Colors.orange,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ExamManagementPage(),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
