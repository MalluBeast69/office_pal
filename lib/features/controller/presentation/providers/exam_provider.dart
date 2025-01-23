import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/data/repositories/exam_repository.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

final examRepositoryProvider =
    Provider<ExamRepository>((ref) => ExamRepository());

final examsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.watch(examRepositoryProvider);
  return repository.getExamHistory();
});
