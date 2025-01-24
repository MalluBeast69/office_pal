import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';
import 'package:intl/intl.dart';

class ExamRepository {
  final _supabase = Supabase.instance.client;

  // Create
  Future<void> scheduleExams(List<Exam> exams) async {
    final courseIds = exams.map((e) => e.courseId).toList();
    final existingExams =
        await _supabase.from('exam').select().inFilter('course_id', courseIds);

    if (existingExams.isNotEmpty) {
      final conflictingCourses =
          existingExams.map((e) => e['course_id'] as String).toList();
      throw Exception(
          'The following courses already have exams scheduled: ${conflictingCourses.join(", ")}');
    }

    final examData = exams.map((exam) => exam.toJson()).toList();
    await _supabase.from('exam').insert(examData);
  }

  // Read
  Future<List<Map<String, dynamic>>> getExams() async {
    final response = await _supabase.from('exam').select('''
      *,
      course:course_id (
        course_code,
        course_name,
        dept_id,
        course_type,
        semester
      )
    ''').order('exam_date', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  // Update
  Future<void> updateExam(String examId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _supabase.from('exam').update(data).eq('exam_id', examId);
  }

  Future<void> postponeExam(
      String examId, DateTime newDate, String reason) async {
    print('Repository: Postponing exam $examId to $newDate');
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(newDate);
      print('Repository: Formatted date: $formattedDate');

      final response = await _supabase.from('exam').update({
        'exam_date': formattedDate,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('exam_id', examId);

      print('Repository: Exam postponed successfully');
      print('Repository: Response: $response');
    } catch (e, stackTrace) {
      print('Repository: Error postponing exam: $e');
      print('Repository: Stack trace: $stackTrace');
      throw Exception('Failed to postpone exam: $e');
    }
  }

  // Delete
  Future<void> deleteExam(String examId) async {
    await _supabase.from('exam').delete().eq('exam_id', examId);
  }

  // Excel operations
  Future<List<Map<String, dynamic>>> generateExcelData() async {
    final response = await _supabase
        .from('exam')
        .select('*, course:course_id(*)')
        .order('exam_date', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }
}
