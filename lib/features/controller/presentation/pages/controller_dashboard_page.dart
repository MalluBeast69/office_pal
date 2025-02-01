import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/presentation/pages/exam_scheduling_page.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/providers/holiday_provider.dart';
import 'package:office_pal/features/controller/domain/services/holiday_service.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:office_pal/features/controller/presentation/pages/exam_management_page.dart';
import 'package:office_pal/shared/widgets/screen_size_warning_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenSizeWarningDialog.showWarningIfNeeded(context, 'controller');
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

  @override
  Widget build(BuildContext context) {
    print('Building ControllerDashboardPage');
    final examsAsync = ref.watch(examsProvider);
    final holidaysAsync = ref.watch(holidaysProvider(_focusedDay.year));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _signOut(context),
        ),
        title: const Text('Controller Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.view_list : Icons.calendar_today),
            onPressed: () {
              setState(() {
                _showCalendar = !_showCalendar;
              });
            },
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome, Controller',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_showCalendar)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: examsAsync.when(
                    data: (exams) {
                      print('Exams data received: ${exams.length} exams');
                      return holidaysAsync.when(
                        data: (holidays) {
                          print(
                              'Holidays data received: ${holidays.length} holidays');
                          return Column(
                            children: [
                              TableCalendar(
                                firstDay: DateTime.now()
                                    .subtract(const Duration(days: 365)),
                                lastDay: DateTime.now()
                                    .add(const Duration(days: 365)),
                                focusedDay: _focusedDay,
                                selectedDayPredicate: (day) =>
                                    isSameDay(_selectedDay, day),
                                calendarFormat: _calendarFormat,
                                onFormatChanged: (format) {
                                  setState(() {
                                    _calendarFormat = format;
                                  });
                                },
                                eventLoader: (day) {
                                  final events =
                                      _getEventsForDay(day, exams, holidays);
                                  print(
                                      'Events for ${day.toString()}: ${events.length}');
                                  return events;
                                },
                                calendarStyle: CalendarStyle(
                                  markerSize: 8,
                                  markerDecoration: BoxDecoration(
                                    color: Colors.blue.shade700,
                                    shape: BoxShape.circle,
                                  ),
                                  markersMaxCount: 3,
                                  markerMargin: const EdgeInsets.symmetric(
                                      horizontal: 0.5),
                                  holidayTextStyle:
                                      const TextStyle(color: Colors.red),
                                  holidayDecoration: const BoxDecoration(),
                                ),
                                holidayPredicate: (day) {
                                  return holidays.any((holiday) =>
                                      holiday.date.year == day.year &&
                                      holiday.date.month == day.month &&
                                      holiday.date.day == day.day);
                                },
                                onDaySelected: (selectedDay, focusedDay) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                  });
                                  _showEventDialog(
                                      context, selectedDay, exams, holidays);
                                },
                              ),
                            ],
                          );
                        },
                        loading: () => const SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (error, stack) {
                          print('Error loading exams: $error');
                          print('Stack trace: $stack');
                          return Center(
                            child: Text('Error loading exams: $error'),
                          );
                        },
                      );
                    },
                    loading: () => const SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, stack) {
                      print('Error loading exams: $error');
                      print('Stack trace: $stack');
                      return Center(
                        child: Text('Error loading exams: $error'),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 32),
            LayoutBuilder(builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 600;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isDesktop ? 4 : 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: isDesktop ? 1.5 : 1.0,
                children: [
                  _buildDashboardCard(
                    context,
                    title: 'Exam Scheduling',
                    icon: Icons.calendar_month,
                    color: Colors.blue,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ExamSchedulingPage(),
                        ),
                      );
                    },
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Exam Management',
                    icon: Icons.manage_history,
                    color: Colors.green,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ExamManagementPage(),
                        ),
                      );
                    },
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
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
                color.withOpacity(0.7),
                color.withOpacity(0.5),
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
}
