import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/providers/course_provider.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/presentation/widgets/excel_preview_dialog.dart'
    as preview;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:office_pal/features/superintendent/presentation/pages/exam_creator_page.dart'
    as creator;

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
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
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
  Set<String> selectedExams = {};

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

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
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
          .select(
              '*, course:course_id(course_code, course_name, course_type, dept_id)')
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const creator.ExamCreatorPage(),
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

    // First, deduplicate exams based on course_id
    final uniqueExams = <String, Map<String, dynamic>>{};
    for (var exam in exams) {
      final courseId = exam['course_id'];
      if (!uniqueExams.containsKey(courseId)) {
        uniqueExams[courseId] = exam;
      }
    }
    exams = uniqueExams.values.toList();

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
    final DateTime initialDate = DateTime.parse(exam['exam_date']);
    DateTime selectedDate = initialDate;
    String selectedSession = exam['session'];
    String selectedTime = exam['time'];
    int selectedDuration = exam['duration'];
    bool hasChanges = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool dialogHasChanges = false; // Local state for the dialog

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Exam'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Course Info (non-editable)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.school,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${exam['course']['course_code']} - ${exam['course']['course_name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Department: ${exam['course']['dept_id']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Date Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exam Date'),
                    subtitle:
                        Text(DateFormat('EEEE, MMM d, y').format(selectedDate)),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null && date != selectedDate) {
                          setDialogState(() {
                            selectedDate = date;
                            dialogHasChanges = true;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Session Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedSession,
                    decoration: const InputDecoration(
                      labelText: 'Session',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'MORNING', child: Text('MORNING')),
                      DropdownMenuItem(
                          value: 'AFTERNOON', child: Text('AFTERNOON')),
                    ],
                    onChanged: (value) {
                      if (value != null && value != selectedSession) {
                        setDialogState(() {
                          selectedSession = value;
                          selectedTime = value == 'MORNING' ? '09:00' : '14:00';
                          dialogHasChanges = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Time Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time'),
                    subtitle: Text(
                      DateFormat('hh:mm a').format(
                        DateFormat('HH:mm').parse(selectedTime),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.access_time),
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            DateFormat('HH:mm').parse(selectedTime),
                          ),
                          builder: (context, child) {
                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                alwaysUse24HourFormat: false,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (time != null) {
                          final hour = time.hour;
                          final isValidTime = selectedSession == 'MORNING'
                              ? hour < 12
                              : hour >= 12 && hour < 18;

                          if (!isValidTime) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    selectedSession == 'MORNING'
                                        ? 'Morning session must be before 12:00 PM'
                                        : 'Afternoon session must be between 12:00 PM and 6:00 PM',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          }

                          final newTime =
                              '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                          if (newTime != selectedTime) {
                            setDialogState(() {
                              selectedTime = newTime;
                              dialogHasChanges = true;
                            });
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Duration Stepper
                  Row(
                    children: [
                      const Text('Duration (mins):'),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: selectedDuration <= 30
                            ? null
                            : () {
                                setDialogState(() {
                                  selectedDuration -= 30;
                                  dialogHasChanges = true;
                                });
                              },
                      ),
                      Container(
                        width: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: TextFormField(
                          initialValue: selectedDuration.toString(),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                          ),
                          onChanged: (value) {
                            final duration = int.tryParse(value);
                            if (duration != null &&
                                duration != selectedDuration) {
                              setDialogState(() {
                                selectedDuration = duration;
                                dialogHasChanges = true;
                              });
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: selectedDuration >= 360
                            ? null
                            : () {
                                setDialogState(() {
                                  selectedDuration += 30;
                                  dialogHasChanges = true;
                                });
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: dialogHasChanges
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Save Changes'),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // Update exam in database
        await Supabase.instance.client.from('exam').update({
          'exam_date': selectedDate.toIso8601String().split('T')[0],
          'session': selectedSession,
          'time': selectedTime,
          'duration': selectedDuration,
        }).eq('exam_id', exam['exam_id']);

        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
        }

        // Refresh exams
        ref.refresh(examsProvider);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exam updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
        }

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating exam: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
      setState(() => isLoading = true);

      // Get all exams with course details
      final response = await Supabase.instance.client
          .from('exam')
          .select(
              '*, course:course_id(course_code, course_name, course_type, dept_id)')
          .order('exam_date');

      final exams = List<Map<String, dynamic>>.from(response);

      if (exams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No exams to export'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Convert to proper format
      final formattedExams = exams.map((exam) {
        final course = exam['course'] as Map<String, dynamic>;
        return {
          'exam_id': exam['exam_id'] as String,
          'course_id': exam['course_id'] as String,
          'course_name': course['course_name'] as String,
          'dept_id': course['dept_id'] as String,
          'exam_date': DateTime.parse(exam['exam_date'] as String),
          'session': exam['session'] as String,
          'time': exam['time'] as String,
          'duration': int.parse(exam['duration'].toString()),
        };
      }).toList();

      // Generate Excel file
      final excelFile = excel.Excel.createExcel();
      final sheet = excelFile.sheets[excelFile.getDefaultSheet()];
      if (sheet == null) throw Exception('Failed to create Excel sheet');

      // Add headers
      final headers = [
        'Exam ID',
        'Course Code',
        'Course Name',
        'Department',
        'Date',
        'Session',
        'Time',
        'Duration (mins)'
      ];

      // Add headers with styling
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel.CellIndex.indexByColumnRow(
          columnIndex: i,
          rowIndex: 0,
        ));
        cell.value = excel.TextCellValue(headers[i]);
        cell.cellStyle = excel.CellStyle(
          bold: true,
          horizontalAlign: excel.HorizontalAlign.Center,
        );
      }

      // Add data
      for (var i = 0; i < formattedExams.length; i++) {
        final exam = formattedExams[i];
        final rowIndex = i + 1;

        // Exam ID
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 0,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['exam_id'] as String);

        // Course Code
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 1,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['course_id'] as String);

        // Course Name
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 2,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['course_name'] as String);

        // Department
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 3,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['dept_id'] as String);

        // Date
        sheet
                .cell(excel.CellIndex.indexByColumnRow(
                  columnIndex: 4,
                  rowIndex: rowIndex,
                ))
                .value =
            excel.TextCellValue(
                DateFormat('MMM d, y').format(exam['exam_date'] as DateTime));

        // Session
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 5,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['session'] as String);

        // Time
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 6,
              rowIndex: rowIndex,
            ))
            .value = excel.TextCellValue(exam['time'] as String);

        // Duration
        sheet
            .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: 7,
              rowIndex: rowIndex,
            ))
            .value = excel.IntCellValue(exam['duration'] as int);
      }

      // Auto-fit columns
      sheet.setColumnWidth(0, 15.0);
      sheet.setColumnWidth(1, 15.0);
      sheet.setColumnWidth(2, 40.0);
      sheet.setColumnWidth(3, 15.0);
      sheet.setColumnWidth(4, 15.0);
      sheet.setColumnWidth(5, 15.0);
      sheet.setColumnWidth(6, 15.0);
      sheet.setColumnWidth(7, 15.0);

      final excelBytes = excelFile.save();
      if (excelBytes == null) throw Exception('Failed to generate Excel file');

      if (!mounted) return;

      // Show preview dialog
      await showDialog(
        context: context,
        builder: (context) => preview.ExcelPreviewDialog(
          excelBytes: excelBytes,
          fileName:
              'exam_schedule_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        ),
      );
    } catch (e) {
      developer.log('Error generating Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $e'),
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

  Future<void> _importFromExcel() async {
    try {
      developer.log('Starting Excel import process...');
      setState(() => isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null) {
        developer.log('No file selected');
        return;
      }

      final file = result.files.first;
      developer.log('File selected: ${file.name}');

      if (file.bytes == null) {
        throw Exception('Could not read file data');
      }

      final excelDoc = excel.Excel.decodeBytes(file.bytes!);
      final sheet = excelDoc.tables[excelDoc.tables.keys.first]!;
      developer.log('Sheet rows: ${sheet.rows.length}');

      List<Map<String, dynamic>> importedExams = [];
      List<String> errors = [];
      List<String> warnings = [];

      // Skip header row
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        developer.log(
            'Processing row $i: ${row.map((cell) => cell?.value).toList()}');

        if (row.isEmpty || row[0]?.value == null) {
          developer.log('Skipping empty row $i');
          continue;
        }

        try {
          final examId = row[0]!.value.toString().trim();
          final courseId = row[1]!.value.toString().trim();
          final courseName = row[2]!.value.toString().trim();
          final department = row[3]!.value.toString().trim();
          final dateStr = row[4]!.value.toString().trim();
          final session = row[5]!.value.toString().trim().toUpperCase();
          final time = row[6]!.value.toString().trim();
          final durationStr = row[7]!.value.toString().trim();

          developer.log(
              'Row $i data: examId=$examId, courseId=$courseId, courseName=$courseName, department=$department, date=$dateStr, session=$session, time=$time, duration=$durationStr');

          // Validate course ID
          if (courseId.isEmpty) {
            developer.log('Row $i: Empty course ID');
            errors.add('Row ${i + 1}: Course ID is required');
            continue;
          }

          // Parse date (expecting format like "Feb 20, 2025")
          DateTime date;
          try {
            date = DateFormat('MMM d, y').parse(dateStr);
            developer.log('Row $i: Successfully parsed date: $date');
          } catch (e) {
            developer.log('Row $i: Date parsing error: $e');
            errors.add(
                'Row ${i + 1}: Invalid date format. Use "MMM d, y" format (e.g., Feb 20, 2025)');
            continue;
          }

          // Validate session
          if (!['MORNING', 'AFTERNOON'].contains(session)) {
            developer.log('Row $i: Invalid session: $session');
            errors.add('Row ${i + 1}: Session must be MORNING or AFTERNOON');
            continue;
          }

          // Validate time format and convert to HH:mm if needed
          String normalizedTime = time;
          if (time.contains(':')) {
            final timeParts = time.split(':');
            if (timeParts.length == 3) {
              // Convert from HH:mm:ss to HH:mm
              normalizedTime = '${timeParts[0]}:${timeParts[1]}';
            }
          }

          final timeRegex = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
          if (!timeRegex.hasMatch(normalizedTime)) {
            developer.log('Row $i: Invalid time format: $time');
            errors.add(
                'Row ${i + 1}: Invalid time format. Use HH:mm or HH:mm:ss');
            continue;
          }

          // Validate time based on session
          final hour = int.parse(normalizedTime.split(':')[0]);
          if (session == 'MORNING' && hour >= 12) {
            developer.log('Row $i: Invalid morning time: $normalizedTime');
            errors.add('Row ${i + 1}: Morning session must be before 12:00');
            continue;
          } else if (session == 'AFTERNOON' && (hour < 12 || hour >= 18)) {
            developer.log('Row $i: Invalid afternoon time: $normalizedTime');
            errors.add(
                'Row ${i + 1}: Afternoon session must be between 12:00 and 18:00');
            continue;
          }

          // Validate duration
          final duration = int.tryParse(durationStr);
          if (duration == null || duration < 30 || duration > 360) {
            developer.log('Row $i: Invalid duration: $durationStr');
            errors.add(
                'Row ${i + 1}: Duration must be between 30 and 360 minutes');
            continue;
          }

          // Check if date is in the past
          if (date.isBefore(DateTime.now())) {
            developer.log('Row $i: Past date warning: $date');
            warnings.add('Row ${i + 1}: Exam date is in the past');
          }

          // Check if date is a Sunday
          if (date.weekday == DateTime.sunday) {
            developer.log('Row $i: Sunday warning');
            warnings.add('Row ${i + 1}: Exam is scheduled on a Sunday');
          }

          importedExams.add({
            'courseId': courseId,
            'date': date,
            'session': session,
            'time': normalizedTime, // Use normalized time without seconds
            'duration': duration,
            'rowNumber': i + 1,
          });
          developer.log('Row $i: Successfully added to importedExams');
        } catch (e) {
          developer.log('Row $i: Processing error: $e');
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      developer.log(
          'Import summary: ${importedExams.length} exams, ${errors.length} errors, ${warnings.length} warnings');

      if (importedExams.isEmpty) {
        throw Exception('No valid exams found in the file');
      }

      // Check for existing exams
      final existingExams = await Supabase.instance.client
          .from('exam')
          .select('course_id, exam_date')
          .in_('course_id', importedExams.map((e) => e['courseId']).toList());

      final existingExamMap = {
        for (var exam in existingExams)
          '${exam['course_id']}_${exam['exam_date']}': exam
      };

      // Check for duplicates within the import
      final seenCombos = <String>{};
      for (var exam in importedExams) {
        final combo =
            '${exam['courseId']}_${exam['date'].toIso8601String().split('T')[0]}';
        if (seenCombos.contains(combo)) {
          warnings.add(
              'Row ${exam['rowNumber']}: Duplicate entry for ${exam['courseId']} on same date');
        }
        seenCombos.add(combo);

        if (existingExamMap.containsKey(combo)) {
          warnings.add(
              'Row ${exam['rowNumber']}: ${exam['courseId']} already has an exam on ${DateFormat('MMM d, y').format(exam['date'])}');
        }
      }

      if (!mounted) return;

      // Show preview dialog
      final dialogResult = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import Preview'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Exams: ${importedExams.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (warnings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Warnings (${warnings.length}):',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ...warnings.map((warning) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 16,
                                        color: Colors.orange.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        warning,
                                        style: TextStyle(
                                          color: Colors.orange.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                        if (errors.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Errors (${errors.length}):',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ...errors.map((error) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline,
                                        size: 16, color: Colors.red.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Preview:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...importedExams.map((exam) {
                    final hasWarning = warnings.any((w) =>
                        w.contains(exam['courseId']) &&
                        w.contains(
                            DateFormat('MMM d, y').format(exam['date'])));
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: hasWarning ? Colors.orange.shade50 : null,
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(exam['courseId']),
                            if (hasWarning) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Colors.orange.shade700),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${DateFormat('MMM d, y').format(exam['date'])} - ${exam['session']} - ${exam['time']} (${exam['duration']} mins)',
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  errors.isEmpty ? () => Navigator.of(context).pop(true) : null,
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (dialogResult == true && mounted) {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // Import exams
        for (var exam in importedExams) {
          final shortId = (DateTime.now().millisecondsSinceEpoch % 10000)
              .toString()
              .padLeft(4, '0');
          await Supabase.instance.client.from('exam').insert({
            'exam_id': 'EX${exam['courseId']}$shortId',
            'course_id': exam['courseId'],
            'exam_date': exam['date'].toIso8601String().split('T')[0],
            'session': exam['session'],
            'time': exam['time'],
            'duration': exam['duration'],
          });
        }

        // Close loading dialog
        if (mounted) {
          Navigator.pop(context);
        }

        // Refresh exams
        ref.refresh(examsProvider);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Successfully imported ${importedExams.length} exams'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing exams: $e'),
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
    final examsAsync = ref.watch(examsProvider);
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Management'),
        actions: [
          // Add select all checkbox
          examsAsync.when(
            data: (exams) {
              final filteredExams = _filterAndSortExams(exams);
              final allCurrentlyShownSelected = filteredExams
                  .every((exam) => selectedExams.contains(exam['exam_id']));
              final hasFilteredExams = filteredExams.isNotEmpty;

              return hasFilteredExams
                  ? Row(
                      children: [
                        Text(
                          'Select All',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Checkbox(
                          value: allCurrentlyShownSelected,
                          tristate: true,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value ?? false) {
                                selectedExams.addAll(
                                  filteredExams
                                      .map((e) => e['exam_id'].toString()),
                                );
                              } else {
                                selectedExams.removeAll(
                                  filteredExams
                                      .map((e) => e['exam_id'].toString()),
                                );
                              }
                            });
                          },
                        ),
                      ],
                    )
                  : const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          if (selectedExams.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedExams,
              tooltip: 'Delete Selected Exams',
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showManualGenerationDialog,
            tooltip: 'Add Exam',
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import Excel',
            onPressed: _importFromExcel,
          ),
          examsAsync.when(
            data: (exams) => IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Generate Excel',
              onPressed: exams.isEmpty ? null : _generateExcelForAllExams,
            ),
            loading: () => const IconButton(
              icon: Icon(Icons.download),
              onPressed: null,
            ),
            error: (_, __) => const IconButton(
              icon: Icon(Icons.download),
              onPressed: null,
            ),
          ),
          const SizedBox(width: 16),
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

              return Scrollbar(
                controller: _verticalScrollController,
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  child: Scrollbar(
                    controller: _horizontalScrollController,
                    notificationPredicate: (notification) =>
                        notification.depth == 0,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width,
                        ),
                        child: DataTable(
                          columnSpacing: 28.0,
                          horizontalMargin: 20.0,
                          headingRowColor: WidgetStateProperty.all(
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          columns: const [
                            DataColumn(label: Text('Exam ID')),
                            DataColumn(label: Expanded(child: Text('Course'))),
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Session')),
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('Duration (mins)')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: filteredExams.map((exam) {
                            final course = courseMap[exam['course_id']];
                            final examDate = DateTime.parse(exam['exam_date']);
                            final isSelected =
                                selectedExams.contains(exam['exam_id']);

                            return DataRow(
                              selected: isSelected,
                              onSelectChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    selectedExams.add(exam['exam_id']);
                                  } else {
                                    selectedExams.remove(exam['exam_id']);
                                  }
                                });
                              },
                              cells: [
                                DataCell(Text(exam['exam_id'])),
                                DataCell(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${course?['course_code']} - ${course?['course_name']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Department: ${course?['dept_id']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(
                                    DateFormat('MMM d, y').format(examDate))),
                                DataCell(Text(exam['session'])),
                                DataCell(Text(
                                  DateFormat('hh:mm a').format(
                                    DateFormat('HH:mm').parse(exam['time']),
                                  ),
                                )),
                                DataCell(Text('${exam['duration']}')),
                                DataCell(_buildStatusBadge(examDate)),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _showEditDialog(exam),
                                        tooltip: 'Edit',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            _showDeleteConfirmation(
                                          Exam.fromJson(exam),
                                        ),
                                        tooltip: 'Delete',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
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

  Future<void> _deleteSelectedExams() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Exams'),
        content: Text(
            'Are you sure you want to delete ${selectedExams.length} selected exams?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isLoading = true);

    try {
      // Delete exams from Supabase
      await Supabase.instance.client
          .from('exam')
          .delete()
          .in_('exam_id', selectedExams.toList());

      // Clear selection and reload exams
      setState(() {
        selectedExams.clear();
      });
      await _loadExams();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected exams deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      developer.log('Error deleting exams: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting exams: $error'),
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
}
