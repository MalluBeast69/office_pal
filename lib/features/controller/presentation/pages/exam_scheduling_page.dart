import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/presentation/widgets/exam_scheduling_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:office_pal/features/controller/presentation/providers/exam_provider.dart';
import 'package:office_pal/features/controller/presentation/widgets/exam_schedule_preview_dialog.dart';
import 'package:office_pal/features/controller/domain/repositories/exam_repository.dart';

enum ExamType { internal, external }

enum ExternalExamType { regular, supplementary }

final selectedCoursesProvider = StateProvider<List<Course>>((ref) => []);
final examTypeProvider = StateProvider<ExamType>((ref) => ExamType.internal);
final externalExamTypeProvider =
    StateProvider<ExternalExamType>((ref) => ExternalExamType.regular);
final selectedSemesterProvider = StateProvider<int?>((ref) => null);
final selectedDepartmentProvider = StateProvider<String?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedCourseTypeProvider = StateProvider<String?>((ref) => null);
final showOnlyUnscheduledProvider = StateProvider<bool>((ref) => false);

class ExamSchedulingPage extends ConsumerStatefulWidget {
  const ExamSchedulingPage({super.key});

  @override
  ConsumerState<ExamSchedulingPage> createState() => _ExamSchedulingPageState();
}

class _ExamSchedulingPageState extends ConsumerState<ExamSchedulingPage> {
  List<Course> _allCourses = [];
  Set<String> _courseTypes = {};
  Set<int> _semesters = {};
  Set<String> _departments = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      setState(() => _isLoading = true);

      final response = await Supabase.instance.client
          .from('course')
          .select()
          .order('course_code');

      if (mounted) {
        final courses =
            (response as List).map((json) => Course.fromJson(json)).toList();
        setState(() {
          _allCourses = courses;
          _courseTypes = courses.map((c) => c.courseType).toSet();
          _semesters = courses.map((c) => c.semester).toSet();
          _departments = courses.map((c) => c.deptId).toSet();
          _isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading courses: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading courses: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Course> _getFilteredCourses() {
    final searchQuery = ref.watch(searchQueryProvider).toLowerCase();
    final selectedSemester = ref.watch(selectedSemesterProvider);
    final selectedCourseType = ref.watch(selectedCourseTypeProvider);
    final selectedDepartment = ref.watch(selectedDepartmentProvider);

    return _allCourses.where((course) {
      if (searchQuery.isNotEmpty) {
        final matchesSearch =
            course.courseCode.toLowerCase().contains(searchQuery) ||
                course.courseName.toLowerCase().contains(searchQuery);
        if (!matchesSearch) return false;
      }

      if (selectedSemester != null && course.semester != selectedSemester) {
        return false;
      }

      if (selectedCourseType != null &&
          course.courseType != selectedCourseType) {
        return false;
      }

      if (selectedDepartment != null && course.deptId != selectedDepartment) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final examType = ref.watch(examTypeProvider);
    final externalType = ref.watch(externalExamTypeProvider);
    final selectedCourses = ref.watch(selectedCoursesProvider);
    final filteredCourses = _getFilteredCourses();
    final examsAsync = ref.watch(examsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Exam'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importFromCSV,
            tooltip: 'Import from Excel',
          ),
          if (selectedCourses.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final exams = await showDialog(
                  context: context,
                  builder: (context) => ExamSchedulingDialog(
                    selectedCourses: selectedCourses,
                  ),
                );

                if (exams != null) {
                  ref.read(selectedCoursesProvider.notifier).state = [];
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exams scheduled successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check),
              label: Text('Schedule (${selectedCourses.length})'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Exam Type Selection
                        const Text(
                          'Exam Type',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: SegmentedButton<ExamType>(
                              segments: const [
                                ButtonSegment(
                                  value: ExamType.internal,
                                  label: Text('Internal'),
                                ),
                                ButtonSegment(
                                  value: ExamType.external,
                                  label: Text('External'),
                                ),
                              ],
                              selected: {examType},
                              onSelectionChanged: (Set<ExamType> newSelection) {
                                ref.read(examTypeProvider.notifier).state =
                                    newSelection.first;
                              },
                            ),
                          ),
                        ),
                        if (examType == ExamType.external) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'External Exam Type',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: SegmentedButton<ExternalExamType>(
                                segments: const [
                                  ButtonSegment(
                                    value: ExternalExamType.regular,
                                    label: Text('Regular'),
                                  ),
                                  ButtonSegment(
                                    value: ExternalExamType.supplementary,
                                    label: Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 4),
                                      child: Text(
                                        'Supplementary',
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ],
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize:
                                      MaterialStateProperty.all(Size.zero),
                                  padding: MaterialStateProperty.all(
                                      EdgeInsets.symmetric(horizontal: 16)),
                                ),
                                selected: {externalType},
                                onSelectionChanged:
                                    (Set<ExternalExamType> newSelection) {
                                  ref
                                      .read(externalExamTypeProvider.notifier)
                                      .state = newSelection.first;
                                },
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Search and Filters
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search by course code or name',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onChanged: (value) {
                            ref.read(searchQueryProvider.notifier).state =
                                value;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Filters Row 1
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: ref.watch(selectedSemesterProvider),
                                decoration: const InputDecoration(
                                  labelText: 'Semester',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('All Semesters'),
                                  ),
                                  ..._semesters
                                      .toList()
                                      .map((semester) => DropdownMenuItem(
                                            value: semester,
                                            child: Text('Semester $semester'),
                                          ))
                                      .toList()
                                    ..sort((a, b) =>
                                        (a.value ?? 0).compareTo(b.value ?? 0)),
                                ],
                                onChanged: (value) {
                                  ref
                                      .read(selectedSemesterProvider.notifier)
                                      .state = value;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: ref.watch(selectedDepartmentProvider),
                                decoration: const InputDecoration(
                                  labelText: 'Department',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('All Departments'),
                                  ),
                                  ..._departments
                                      .toList()
                                      .map((dept) => DropdownMenuItem(
                                            value: dept,
                                            child: Text(dept),
                                          ))
                                      .toList()
                                    ..sort((a, b) => (a.value ?? '')
                                        .compareTo(b.value ?? '')),
                                ],
                                onChanged: (value) {
                                  ref
                                      .read(selectedDepartmentProvider.notifier)
                                      .state = value;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Course Type Filter
                        DropdownButtonFormField<String>(
                          value: ref.watch(selectedCourseTypeProvider),
                          decoration: const InputDecoration(
                            labelText: 'Course Type',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All Types'),
                            ),
                            ..._courseTypes
                                .toList()
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type.toUpperCase()),
                                    ))
                                .toList()
                              ..sort((a, b) =>
                                  (a.value ?? '').compareTo(b.value ?? '')),
                          ],
                          onChanged: (value) {
                            ref
                                .read(selectedCourseTypeProvider.notifier)
                                .state = value;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Show only unscheduled toggle
                        SwitchListTile(
                          title: const Text('Show only unscheduled courses'),
                          value: ref.watch(showOnlyUnscheduledProvider),
                          onChanged: (value) {
                            ref
                                .read(showOnlyUnscheduledProvider.notifier)
                                .state = value;
                          },
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: examsAsync.when(
                    data: (exams) {
                      final scheduledCourses =
                          exams.map((e) => e['course_id'] as String).toSet();

                      // Filter out scheduled courses if toggle is on
                      final showOnlyUnscheduled =
                          ref.watch(showOnlyUnscheduledProvider);
                      final displayCourses = showOnlyUnscheduled
                          ? filteredCourses
                              .where((course) =>
                                  !scheduledCourses.contains(course.courseCode))
                              .toList()
                          : filteredCourses;

                      return ListView.builder(
                        itemCount: displayCourses.length,
                        itemBuilder: (context, index) {
                          final course = displayCourses[index];
                          final isSelected = selectedCourses.contains(course);
                          final hasExamScheduled =
                              scheduledCourses.contains(course.courseCode);

                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(course.courseCode),
                                ),
                                if (hasExamScheduled)
                                  Tooltip(
                                    message: 'Exam already scheduled',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange.shade200,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 16,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Scheduled',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(course.courseName),
                                Text(
                                  'Semester ${course.semester} | ${course.deptId} | ${course.courseType.toUpperCase()} | ${course.credit} Credits',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            value: isSelected,
                            onChanged: hasExamScheduled
                                ? null // Disable selection if exam is already scheduled
                                : (bool? value) {
                                    if (value == true) {
                                      ref
                                          .read(
                                              selectedCoursesProvider.notifier)
                                          .state = [
                                        ...selectedCourses,
                                        course,
                                      ];
                                    } else {
                                      ref
                                              .read(selectedCoursesProvider
                                                  .notifier)
                                              .state =
                                          selectedCourses
                                              .where((c) => c != course)
                                              .toList();
                                    }
                                  },
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stack) => Center(
                      child: Text('Error: $error'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _importFromCSV() async {
    try {
      print('Starting file picker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      print('File picker result: ${result?.files.length ?? 0} files');
      if (result != null) {
        final file = result.files.first;
        print('File name: ${file.name}');
        print('File size: ${file.size} bytes');

        if (file.bytes == null) {
          throw Exception('No file content');
        }

        print('Decoding Excel file...');
        final excelDoc = excel.Excel.decodeBytes(file.bytes!);
        final sheet = excelDoc.tables[excelDoc.tables.keys.first]!;
        print('Sheet rows: ${sheet.rows.length}');

        List<Exam> importedExams = [];

        // Skip header row
        for (var i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          print(
              'Processing row $i: ${row.map((cell) => cell?.value).toList()}');

          if (row.isEmpty || row[0]?.value == null) {
            print('Skipping empty row $i');
            continue;
          }

          try {
            final courseId = row[0]!.value.toString();
            final date = DateTime.parse(row[1]!.value.toString());
            final session = row[2]!.value.toString().toUpperCase();
            final time = row[3]!.value.toString();
            final duration = int.parse(row[4]!.value.toString());

            print(
                'Parsed row $i: courseId=$courseId, date=$date, session=$session, time=$time, duration=$duration');

            importedExams.add(Exam(
              examId:
                  'EX$courseId${DateTime.now().millisecondsSinceEpoch % 10000}',
              courseId: courseId,
              examDate: date,
              session: session,
              time: time,
              duration: duration,
            ));
          } catch (e, stackTrace) {
            print('Error parsing row $i: $e');
            print('Stack trace: $stackTrace');
            continue;
          }
        }

        print('Total exams imported: ${importedExams.length}');

        if (importedExams.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No valid exams found in the file'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Schedule the imported exams
        final repository = ref.read(examRepositoryProvider);
        await repository.scheduleExams(importedExams);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${importedExams.length} exams imported successfully'),
              backgroundColor: Colors.green,
            ),
          );
          ref.refresh(examsProvider);
        }
      }
    } catch (error, stackTrace) {
      print('Error importing exams: $error');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing exams: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
