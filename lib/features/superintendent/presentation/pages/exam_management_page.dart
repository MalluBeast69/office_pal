import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'timetable_generation_page.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/providers/course_provider.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/presentation/widgets/excel_preview_dialog.dart';
import 'package:office_pal/features/controller/utils/exam_timetable_excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;

enum ExamSortOption {
  date('Date'),
  course('Course'),
  session('Session');

  final String label;
  const ExamSortOption(this.label);
}

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
  bool _showToday = true;
  bool _showUpcoming = true;
  bool _showPast = true;
  String _searchQuery = '';
  ExamSortOption _sortOption = ExamSortOption.date;
  bool _sortAscending = true;

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
    // Add listener to refresh exams when page gains focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(examsProvider);
    });
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

  Widget _buildExamList(List<Map<String, dynamic>> exams) {
    if (exams.isEmpty) {
      return const Center(
        child: Text('No exams scheduled'),
      );
    }

    final filteredExams = _filterAndSortExams(exams);

    return ListView.builder(
      itemCount: filteredExams.length,
      itemBuilder: (context, index) {
        final exam = filteredExams[index];
        final course = exam['course'] as Map<String, dynamic>;
        final examDate = DateTime.parse(exam['exam_date']);
        final isToday = _isToday(examDate);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Row(
              children: [
                Text('${course['course_code']} - ${course['course_name']}'),
                const SizedBox(width: 8),
                _buildStatusBadge(examDate),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${DateFormat('MMM d, y').format(examDate)}',
                ),
                Text(
                  'Session: ${exam['session']}, Time: ${exam['time']}, Duration: ${exam['duration']} mins',
                ),
                Text(
                  'Department: ${course['dept_id']}',
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditDialog(exam),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _showDeleteConfirmation(Exam.fromJson(exam)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  List<Map<String, dynamic>> _filterAndSortExams(
      List<Map<String, dynamic>> exams) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return exams.where((exam) {
      // Search filter
      final course = exam['course'] as Map<String, dynamic>?;
      if (course == null) return false;

      final courseCode = course['course_code']?.toString().toLowerCase() ?? '';
      final courseName = course['course_name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();

      if (!courseCode.contains(searchLower) &&
          !courseName.contains(searchLower)) {
        return false;
      }

      // Date filters
      final examDate = DateTime.parse(exam['exam_date']);
      final examDay = DateTime(examDate.year, examDate.month, examDate.day);

      final isToday = examDay.isAtSameMomentAs(today);
      final isUpcoming = examDay.isAfter(today);
      final isPast = examDay.isBefore(today);

      if (isToday && !_showToday) return false;
      if (isUpcoming && !_showUpcoming) return false;
      if (isPast && !_showPast) return false;

      return true;
    }).toList()
      ..sort((a, b) {
        switch (_sortOption) {
          case ExamSortOption.date:
            final aDate = DateTime.parse(a['exam_date']);
            final bDate = DateTime.parse(b['exam_date']);
            return _sortAscending
                ? aDate.compareTo(bDate)
                : bDate.compareTo(aDate);
          case ExamSortOption.course:
            final aCourse =
                (a['course'] as Map<String, dynamic>?)?['course_code']
                        ?.toString() ??
                    '';
            final bCourse =
                (b['course'] as Map<String, dynamic>?)?['course_code']
                        ?.toString() ??
                    '';
            return _sortAscending
                ? aCourse.compareTo(bCourse)
                : bCourse.compareTo(aCourse);
          case ExamSortOption.session:
            final aSession = a['session']?.toString() ?? '';
            final bSession = b['session']?.toString() ?? '';
            return _sortAscending
                ? aSession.compareTo(bSession)
                : bSession.compareTo(aSession);
        }
      });
  }

  Widget _buildStatusBadge(DateTime examDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDay = DateTime(examDate.year, examDate.month, examDate.day);

    if (examDay.isAtSameMomentAs(today)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
            SizedBox(width: 4),
            Text('Today', style: TextStyle(color: Colors.orange)),
          ],
        ),
      );
    } else if (examDay.isBefore(today)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 16, color: Colors.grey),
            SizedBox(width: 4),
            Text('Past', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text('Upcoming', style: TextStyle(color: Colors.green)),
          ],
        ),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> exam) async {
    // TODO: Implement edit dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit functionality coming soon')),
    );
  }

  Future<void> _showDeleteConfirmation(Exam exam) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exam'),
        content: Text(
            'Are you sure you want to delete the exam for ${exam.courseId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final repository = ref.read(examRepositoryProvider);
        await repository.deleteExam(exam.examId);
        ref.refresh(examsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting exam: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _generateExcelForAllExams() async {
    try {
      final examRepository = ref.read(examRepositoryProvider);
      final courseRepository = ref.read(courseRepositoryProvider);

      final exams = await examRepository.generateExcelData();
      final courses = await courseRepository.getCourses();

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => ExcelPreviewDialog(
          excelBytes: ExamTimetableExcel.generate(
            exams.map((e) => Exam.fromJson(e)).toList(),
            courses.map((c) => Course.fromJson(c)).toList(),
          ),
          fileName:
              'all_exams_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating Excel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider);
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Generate Timetable',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TimetableGenerationPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Generate Excel',
            onPressed: _generateExcelForAllExams,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by course code or name',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // Sort options
                    DropdownButton<ExamSortOption>(
                      value: _sortOption,
                      items: ExamSortOption.values.map((option) {
                        return DropdownMenuItem(
                          value: option,
                          child: Text('Sort by ${option.label}'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortOption = value);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(_sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward),
                      onPressed: () =>
                          setState(() => _sortAscending = !_sortAscending),
                      tooltip: _sortAscending ? 'Ascending' : 'Descending',
                    ),
                    const SizedBox(width: 16),
                    // Filter chips
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.orange),
                          SizedBox(width: 4),
                          Text('Today'),
                        ],
                      ),
                      selected: _showToday,
                      selectedColor: Colors.orange.withOpacity(0.2),
                      checkmarkColor: Colors.orange,
                      onSelected: (value) => setState(() => _showToday = value),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_available,
                              size: 16, color: Colors.green),
                          SizedBox(width: 4),
                          Text('Upcoming'),
                        ],
                      ),
                      selected: _showUpcoming,
                      selectedColor: Colors.green.withOpacity(0.2),
                      checkmarkColor: Colors.green,
                      onSelected: (value) =>
                          setState(() => _showUpcoming = value),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 16, color: Colors.grey),
                          SizedBox(width: 4),
                          Text('Past'),
                        ],
                      ),
                      selected: _showPast,
                      selectedColor: Colors.grey.withOpacity(0.2),
                      checkmarkColor: Colors.grey,
                      onSelected: (value) => setState(() => _showPast = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: examsAsync.when(
        data: (exams) {
          if (exams.isEmpty) {
            return const Center(
              child: Text('No exams scheduled yet'),
            );
          }

          return coursesAsync.when(
            data: (courses) {
              final courseMap = {
                for (var course in courses) course['course_code']: course
              };

              final filteredExams = _filterAndSortExams(exams);

              return ListView.builder(
                itemCount: filteredExams.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final exam = Exam.fromJson(filteredExams[index]);
                  final course = courseMap[exam.courseId];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                                '${exam.courseId} - ${course?['course_name'] ?? 'Unknown Course'}'),
                          ),
                          _buildStatusBadge(exam.examDate),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Department: ${course?['dept_id'] ?? 'Unknown Dept'}'),
                          Text(
                              'Date: ${DateFormat('MMM d, y').format(exam.examDate)}'),
                          Text('Session: ${exam.session}, Time: ${exam.time}'),
                          Text('Duration: ${exam.duration} mins'),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete',
                        onPressed: () => _showDeleteConfirmation(exam),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading courses: $error'),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading exams: $error'),
        ),
      ),
    );
  }
}
