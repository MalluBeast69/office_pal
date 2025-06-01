import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/data/repositories/course_repository.dart';

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository();
});

final coursesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.read(courseRepositoryProvider);
  return repository.getCourses();
});
