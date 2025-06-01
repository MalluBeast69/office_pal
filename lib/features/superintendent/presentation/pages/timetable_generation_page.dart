import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

class TimetableGenerationPage extends ConsumerStatefulWidget {
  const TimetableGenerationPage({super.key});

  @override
  ConsumerState<TimetableGenerationPage> createState() =>
      _TimetableGenerationPageState();
}

class _TimetableGenerationPageState
    extends ConsumerState<TimetableGenerationPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> courses = [];
  List<Map<String, dynamic>> halls = [];
  List<Map<String, dynamic>> faculty = [];
  List<Map<String, dynamic>> generatedTimetable = [];
  final _formKey = GlobalKey<FormState>();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load courses
      final coursesResponse = await Supabase.instance.client
          .from('course')
          .select()
          .order('course_code');

      // Load halls
      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true)
          .order('hall_id');

      // Load faculty
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .eq('is_available', true)
          .order('faculty_id');

      if (mounted) {
        setState(() {
          courses = List<Map<String, dynamic>>.from(coursesResponse);
          halls = List<Map<String, dynamic>>.from(hallsResponse);
          faculty = List<Map<String, dynamic>>.from(facultyResponse);
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

  Future<void> _generateTimetable() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      developer.log('Starting timetable generation process');
      developer.log(
          'Initial data counts - Courses: ${courses.length}, Halls: ${halls.length}, Faculty: ${faculty.length}');

      // Sort courses by course type priority (major > minor > common)
      final sortedCourses = List<Map<String, dynamic>>.from(courses)
        ..sort((a, b) {
          final aPriority = _getCoursePriority(a['course_type']);
          final bPriority = _getCoursePriority(b['course_type']);
          return aPriority.compareTo(bPriority);
        });

      developer.log(
          'Sorted courses by priority: ${sortedCourses.map((c) => '${c['course_code']}(${c['course_type']})').join(', ')}');

      final startDate = DateTime.parse(_startDateController.text);
      final endDate = DateTime.parse(_endDateController.text);
      final availableDates = _generateDateRange(startDate, endDate);
      developer.log(
          'Generated date range: ${availableDates.length} days from $startDate to $endDate');

      final sessions = ['Morning', 'Afternoon'];
      generatedTimetable = [];

      // Assign halls and time slots to exams
      for (final course in sortedCourses) {
        developer.log(
            '\nProcessing course: ${course['course_code']} (${course['course_type']})');
        bool assigned = false;

        // Try to find a suitable slot
        for (final date in availableDates) {
          if (assigned) break;

          for (final session in sessions) {
            if (assigned) break;
            developer
                .log('  Trying slot: ${date.toIso8601String()} - $session');

            // Check if this slot is already taken
            final conflictingExam = generatedTimetable.any((exam) =>
                exam['date'] == date.toIso8601String() &&
                exam['session'] == session);

            if (conflictingExam) {
              developer.log('  Slot already taken');
              continue;
            }

            // Find available hall
            final availableHalls = halls
                .where((hall) => !generatedTimetable.any((exam) =>
                    exam['date'] == date.toIso8601String() &&
                    exam['session'] == session &&
                    exam['hall_id'] == hall['hall_id']))
                .toList();

            developer.log(
                '  Available halls: ${availableHalls.map((h) => h['hall_id']).join(', ')}');

            if (availableHalls.isNotEmpty) {
              final availableHall = availableHalls.first;

              // Find available faculty
              final availableFaculty = faculty
                  .where((f) =>
                      f['dept_id'] == course['dept_id'] &&
                      !generatedTimetable.any((exam) =>
                          exam['date'] == date.toIso8601String() &&
                          exam['session'] == session &&
                          exam['faculty_id'] == f['faculty_id']))
                  .toList();

              developer.log(
                  '  Available faculty: ${availableFaculty.map((f) => f['faculty_id']).join(', ')}');

              if (availableFaculty.isNotEmpty) {
                final selectedFaculty = availableFaculty.first;

                // Add exam to timetable
                final examEntry = {
                  'exam_id': 'EX${course['course_code']}',
                  'course_id': course['course_code'],
                  'date': date.toIso8601String(),
                  'session': session,
                  'time': session == 'Morning' ? '09:00' : '14:00',
                  'duration': 180,
                  'hall_id': availableHall['hall_id'],
                  'faculty_id': selectedFaculty['faculty_id'],
                };
                generatedTimetable.add(examEntry);
                developer.log(
                    '  Successfully assigned exam: ${examEntry.toString()}');

                assigned = true;
              } else {
                developer.log(
                    '  No available faculty found for department ${course['dept_id']}');
              }
            } else {
              developer.log('  No available halls found');
            }
          }
        }

        if (!assigned) {
          developer.log(
              'WARNING: Could not assign exam for course ${course['course_code']}');
        }
      }

      developer.log('\nTimetable generation completed');
      developer.log('Total exams scheduled: ${generatedTimetable.length}');
      developer.log(
          'Unscheduled courses: ${sortedCourses.length - generatedTimetable.length}');

      // Save generated timetable to database
      if (generatedTimetable.isNotEmpty) {
        developer.log('Starting database update');

        // First, clear existing exam allocations
        developer.log('Clearing existing exam records');
        await Supabase.instance.client.from('exam').delete().neq('exam_id', '');

        // Insert exams
        developer.log('Inserting new exam records');
        final examRecords = generatedTimetable
            .map((exam) => {
                  'exam_id': exam['exam_id'],
                  'course_id': exam['course_id'],
                  'exam_date': exam['date'],
                  'session': exam['session'],
                  'time': exam['time'],
                  'duration': exam['duration'],
                })
            .toList();
        await Supabase.instance.client.from('exam').insert(examRecords);

        // Insert exam allocations
        developer.log('Inserting exam allocation records');
        final allocationRecords = generatedTimetable
            .map((exam) => {
                  'hall_id': exam['hall_id'],
                  'faculty_id': exam['faculty_id'],
                  'exam_id': exam['exam_id'],
                })
            .toList();
        await Supabase.instance.client
            .from('exam_allocation')
            .insert(allocationRecords);

        developer.log('Database update completed successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Timetable generated and saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        developer.log('ERROR: No exams could be scheduled');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not generate a complete timetable. Please adjust parameters.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      developer.log('ERROR in timetable generation: $error');
      developer.log('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating timetable: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  int _getCoursePriority(String courseType) {
    switch (courseType) {
      case 'major':
        return 0;
      case 'minor1':
        return 1;
      case 'minor2':
        return 2;
      case 'common':
        return 3;
      default:
        return 4;
    }
  }

  List<DateTime> _generateDateRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var current = start;

    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      // Only include weekdays (Monday to Friday)
      if (current.weekday <= 5) {
        dates.add(current);
      }
      current = current.add(const Duration(days: 1));
    }

    return dates;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Timetable'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Timetable Parameters',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _startDateController,
                                    decoration: const InputDecoration(
                                      labelText: 'Start Date',
                                      border: OutlineInputBorder(),
                                    ),
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 365)),
                                      );
                                      if (date != null) {
                                        _startDateController.text = date
                                            .toIso8601String()
                                            .split('T')[0];
                                      }
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please select start date';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _endDateController,
                                    decoration: const InputDecoration(
                                      labelText: 'End Date',
                                      border: OutlineInputBorder(),
                                    ),
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 365)),
                                      );
                                      if (date != null) {
                                        _endDateController.text = date
                                            .toIso8601String()
                                            .split('T')[0];
                                      }
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please select end date';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  'Available Halls: ${halls.length}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 24),
                                Text(
                                  'Available Faculty: ${faculty.length}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 24),
                                Text(
                                  'Total Courses: ${courses.length}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _generateTimetable,
                                child: const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'Generate Timetable',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (generatedTimetable.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Generated Timetable',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: generatedTimetable.length,
                      itemBuilder: (context, index) {
                        final exam = generatedTimetable[index];
                        return Card(
                          child: ListTile(
                            title: Text(exam['course_id']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Date: ${exam['date'].toString().split('T')[0]}'),
                                Text('Session: ${exam['session']}'),
                                Text('Time: ${exam['time']}'),
                                Text('Hall: ${exam['hall_id']}'),
                                Text('Faculty: ${exam['faculty_id']}'),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
