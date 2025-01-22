import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Exam'),
        centerTitle: true,
        actions: [
          if (selectedCourses.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                // TODO: Implement final scheduling
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Scheduling will be implemented soon')),
                );
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
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredCourses.length,
                    itemBuilder: (context, index) {
                      final course = filteredCourses[index];
                      final isSelected = selectedCourses.contains(course);

                      return CheckboxListTile(
                        title: Text(course.courseCode),
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
                        onChanged: (bool? value) {
                          if (value == true) {
                            ref.read(selectedCoursesProvider.notifier).state = [
                              ...selectedCourses,
                              course,
                            ];
                          } else {
                            ref.read(selectedCoursesProvider.notifier).state =
                                selectedCourses
                                    .where((c) => c != course)
                                    .toList();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
