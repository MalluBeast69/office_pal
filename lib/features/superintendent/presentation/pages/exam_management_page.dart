import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'timetable_generation_page.dart';

class ExamManagementPage extends ConsumerStatefulWidget {
  const ExamManagementPage({super.key});

  @override
  ConsumerState<ExamManagementPage> createState() => _ExamManagementPageState();
}

class _ExamManagementPageState extends ConsumerState<ExamManagementPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> exams = [];
  List<Map<String, dynamic>> filteredExams = [];
  List<Map<String, dynamic>> courses = [];
  String? selectedCourse;
  String? selectedExamType;
  DateTime? selectedDate;
  String? selectedSession;
  final _formKey = GlobalKey<FormState>();

  final List<String> examTypes = [
    'common1',
    'common2',
    'minor1',
    'minor2',
    'major',
    'specific'
  ];
  final List<String> sessions = ['Morning', 'Afternoon'];

  @override
  void initState() {
    super.initState();
    _loadExams();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final response = await Supabase.instance.client
          .from('course')
          .select()
          .order('course_code');

      if (mounted) {
        setState(() {
          courses = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (error) {
      developer.log('Error loading courses: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading courses: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadExams() async {
    setState(() => isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('exam')
          .select('*, course:course_id(course_type)')
          .order('exam_date');

      if (mounted) {
        setState(() {
          exams = List<Map<String, dynamic>>.from(response);
          filteredExams = List.from(exams);
          isLoading = false;
        });
      }
    } catch (error) {
      developer.log('Error loading exams: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading exams: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _applyFilters() {
    setState(() {
      filteredExams = exams.where((exam) {
        bool matchesCourse = selectedCourse == null ||
            exam['course_id'].toString() == selectedCourse;
        return matchesCourse;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      selectedCourse = null;
      filteredExams = List.from(exams);
    });
  }

  void _showManualGenerationDialog() {
    selectedDate = null;
    selectedSession = null;
    selectedExamType = null;
    selectedCourse = null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Exam Generation'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date Picker
                ListTile(
                  title: Text(selectedDate == null
                      ? 'Select Date'
                      : 'Date: ${selectedDate!.toIso8601String().split('T')[0]}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() => selectedDate = date);
                    }
                  },
                ),
                // Session Dropdown
                DropdownButtonFormField<String>(
                  value: selectedSession,
                  decoration: const InputDecoration(labelText: 'Session'),
                  items: sessions.map<DropdownMenuItem<String>>((session) {
                    return DropdownMenuItem<String>(
                      value: session,
                      child: Text(session),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedSession = value);
                  },
                ),
                // Exam Type Dropdown
                DropdownButtonFormField<String>(
                  value: selectedExamType,
                  decoration: const InputDecoration(labelText: 'Exam Type'),
                  items: examTypes.map<DropdownMenuItem<String>>((type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedExamType = value;
                      if (value != 'specific') {
                        selectedCourse = null;
                      }
                    });
                  },
                ),
                // Course Dropdown (only visible when exam type is 'specific')
                if (selectedExamType == 'specific')
                  DropdownButtonFormField<String>(
                    value: selectedCourse,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: courses.map<DropdownMenuItem<String>>((course) {
                      return DropdownMenuItem<String>(
                        value: course['course_code'],
                        child: Text(
                            '${course['course_code']} - ${course['course_name']}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedCourse = value);
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _generateExam,
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateExam() async {
    if (selectedDate == null ||
        selectedSession == null ||
        selectedExamType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (selectedExamType == 'specific' && selectedCourse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a course'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      // Get relevant courses based on exam type
      List<Map<String, dynamic>> targetCourses = [];
      if (selectedExamType == 'specific') {
        targetCourses = courses
            .where((course) => course['course_code'] == selectedCourse)
            .toList();
      } else {
        targetCourses = courses
            .where((course) => course['course_type'] == selectedExamType)
            .toList();
      }

      // Generate exam entries
      for (var course in targetCourses) {
        // Create a shorter unique identifier using the last 4 digits of timestamp
        final shortId = (DateTime.now().millisecondsSinceEpoch % 10000)
            .toString()
            .padLeft(4, '0');
        await Supabase.instance.client.from('exam').insert({
          'exam_id': 'EX${course['course_code']}$shortId',
          'course_id': course['course_code'],
          'exam_date': selectedDate!.toIso8601String().split('T')[0],
          'session': selectedSession,
          'time': selectedSession == 'Morning' ? '09:00' : '14:00',
          'duration': 180,
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exams generated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadExams();
      }
    } catch (error) {
      developer.log('Error generating exams: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating exams: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteExam(String examId) async {
    try {
      await Supabase.instance.client
          .from('exam')
          .delete()
          .eq('exam_id', examId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exam deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadExams();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting exam: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getExamTypeColor(String type) {
    switch (type) {
      case 'major':
        return Colors.blue;
      case 'minor1':
        return Colors.purple;
      case 'minor2':
        return Colors.orange;
      case 'common1':
        return Colors.green;
      case 'common2':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TimetableGenerationPage(),
                ),
              );
            },
            tooltip: 'Generate Timetable',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showManualGenerationDialog,
            tooltip: 'Manual Generation',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCourse,
                            decoration: const InputDecoration(
                              labelText: 'Course',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('All Courses'),
                              ),
                              ...courses.map<DropdownMenuItem<String>>(
                                  (course) => DropdownMenuItem<String>(
                                        value: course['course_code'],
                                        child: Text(course['course_code']),
                                      )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedCourse = value;
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Exams list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredExams.isEmpty
                    ? const Center(
                        child: Text(
                          'No exams found',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredExams.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final exam = filteredExams[index];
                          final courseType =
                              exam['course']['course_type'] ?? 'unknown';
                          return Card(
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(child: Text(exam['exam_id'])),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getExamTypeColor(courseType)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _getExamTypeColor(courseType),
                                      ),
                                    ),
                                    child: Text(
                                      courseType.toUpperCase(),
                                      style: TextStyle(
                                        color: _getExamTypeColor(courseType),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Course: ${exam['course_id']}'),
                                  Text('Date: ${exam['exam_date']}'),
                                  Text('Session: ${exam['session']}'),
                                  Text('Time: ${exam['time']}'),
                                  Text('Duration: ${exam['duration']} minutes'),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Exam'),
                                    content: Text(
                                        'Are you sure you want to delete ${exam['exam_id']}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteExam(exam['exam_id']);
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
