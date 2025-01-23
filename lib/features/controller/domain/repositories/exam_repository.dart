import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamRepository {
  final _supabase = Supabase.instance.client;

  Future<void> scheduleExams(List<Exam> exams) async {
    // First check if any of these courses already have exams scheduled
    final courseIds = exams.map((e) => e.courseId).toList();
    final existingExams = await _supabase
        .from('exam_history')
        .select()
        .inFilter('course_id', courseIds)
        .isFilter('deleted_at', null);

    if (existingExams.isNotEmpty) {
      final conflictingCourses =
          existingExams.map((e) => e['course_id'] as String).toList();
      throw Exception(
          'The following courses already have exams scheduled: ${conflictingCourses.join(", ")}');
    }

    // If no conflicts, insert the new exams
    final examData = exams
        .map((exam) => {
              'course_id': exam.courseId,
              'exam_date': exam.examDate.toIso8601String(),
              'session': exam.session,
              'time': exam.time,
              'duration': exam.duration,
            })
        .toList();

    await _supabase.from('exam_history').insert(examData);
  }

  Future<List<Map<String, dynamic>>> getExamHistory() async {
    final response = await _supabase
        .from('exam_history')
        .select('*, course!inner(*)')
        .isFilter('deleted_at', null)
        .order('exam_date');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deleteExamHistory(String id) async {
    await _supabase
        .from('exam_history')
        .update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }
}
