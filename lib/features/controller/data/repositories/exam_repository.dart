import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Exam>> getExams() async {
    final response = await _client.from('exam').select();
    return (response as List).map((json) => Exam.fromJson(json)).toList();
  }

  Future<void> scheduleExams(List<Exam> exams) async {
    final examData = exams.map((exam) => exam.toJson()).toList();
    await _client.from('exam').insert(examData);
  }

  Future<void> deleteExam(String examId) async {
    await _client.from('exam').delete().eq('exam_id', examId);
  }

  Future<void> updateExam(Exam exam) async {
    await _client.from('exam').update(exam.toJson()).eq('exam_id', exam.examId);
  }
}
