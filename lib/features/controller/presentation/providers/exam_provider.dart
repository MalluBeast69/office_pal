import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/data/repositories/exam_repository.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

final examRepositoryProvider =
    Provider<ExamRepository>((ref) => ExamRepository());

final examsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.watch(examRepositoryProvider);
  return repository.getExams();
});

final selectedExamProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

final examFilterProvider =
    StateProvider<ExamFilter>((ref) => const ExamFilter());

class ExamFilter {
  final bool showToday;
  final bool showUpcoming;
  final bool showPast;
  final String searchQuery;

  const ExamFilter({
    this.showToday = true,
    this.showUpcoming = true,
    this.showPast = false,
    this.searchQuery = '',
  });

  ExamFilter copyWith({
    bool? showToday,
    bool? showUpcoming,
    bool? showPast,
    String? searchQuery,
  }) {
    return ExamFilter(
      showToday: showToday ?? this.showToday,
      showUpcoming: showUpcoming ?? this.showUpcoming,
      showPast: showPast ?? this.showPast,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
