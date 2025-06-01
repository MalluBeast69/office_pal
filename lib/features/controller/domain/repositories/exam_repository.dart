import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamRepository {
  final _supabase = Supabase.instance.client;

  Future<bool> hasExistingExam(String courseId, DateTime examDate) async {
    try {
      print('Checking for existing exam - Course: $courseId, Date: $examDate');
      final formattedDate =
          "${examDate.year}-${examDate.month.toString().padLeft(2, '0')}-${examDate.day.toString().padLeft(2, '0')}";

      final response = await _supabase
          .from('exam')
          .select()
          .eq('course_id', courseId)
          .eq('exam_date', formattedDate);

      final exists = response.isNotEmpty;
      print('Existing exam found: $exists');
      return exists;
    } catch (e) {
      print('Error checking for existing exam: $e');
      rethrow;
    }
  }

  Future<void> scheduleExams(List<Exam> exams) async {
    print('\n=== Starting exam scheduling in repository ===');
    print('Number of exams to schedule: ${exams.length}');

    // Check for duplicates first
    for (var exam in exams) {
      if (await hasExistingExam(exam.courseId, exam.examDate)) {
        throw Exception(
            'An exam for ${exam.courseId} is already scheduled on ${exam.examDate}');
      }
    }

    // If no duplicates, proceed with scheduling
    for (var exam in exams) {
      print('\nProcessing exam:');
      print('  examId: "${exam.examId}" (${exam.examId.length} chars)');
      print('  courseId: "${exam.courseId}" (${exam.courseId.length} chars)');

      // Format date as YYYY-MM-DD to match database format
      final formattedDate =
          "${exam.examDate.year}-${exam.examDate.month.toString().padLeft(2, '0')}-${exam.examDate.day.toString().padLeft(2, '0')}";
      print('  examDate: "$formattedDate" (${formattedDate.length} chars)');

      print('  session: "${exam.session}" (${exam.session.length} chars)');
      print('  time: "${exam.time}" (${exam.time.length} chars)');
      print('  duration: ${exam.duration}');

      final examData = {
        'exam_id': exam.examId,
        'course_id': exam.courseId,
        'exam_date': formattedDate,
        'session': exam.session,
        'time': exam.time,
        'duration': exam.duration,
      };

      print('\nPrepared data for database:');
      examData.forEach((key, value) {
        print('  $key: "$value" (${value.toString().length} chars)');
      });

      try {
        print('\nAttempting database insert...');
        final response = await _supabase.from('exam').insert(examData);
        print('Insert successful. Response: $response');
      } catch (e) {
        print('\nDatabase insert failed:');
        print('Error type: ${e.runtimeType}');
        print('Error details: $e');

        if (e is PostgrestException) {
          print('PostgrestException details:');
          print('  Message: ${e.message}');
          print('  Code: ${e.code}');
          print('  Details: ${e.details}');
          print('  Hint: ${e.hint}');
        }

        rethrow;
      }
    }

    print('\n=== Exam scheduling completed ===\n');
  }

  Future<List<Map<String, dynamic>>> getExams() async {
    try {
      print('Fetching exams from database...');
      final response = await _supabase
          .from('exam')
          .select('*, course:course_id(*)')
          .order('exam_date', ascending: true);

      print('Retrieved ${response.length} exams');
      for (var exam in response) {
        print(
            'Exam ID: ${exam['exam_id']}, Course: ${exam['course_id']}, Date: ${exam['exam_date']}');
      }

      return response;
    } catch (e) {
      print('Error fetching exams: $e');
      rethrow;
    }
  }

  Future<void> deleteExam(String examId) async {
    print('Deleting exam with ID: $examId');
    await _supabase.from('exam').delete().eq('exam_id', examId);
  }

  Future<List<Map<String, dynamic>>> getExamHistory() async {
    final response = await _supabase
        .from('exam_history')
        .select('*, course!inner(*)')
        .is_('deleted_at', null)
        .order('exam_date');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deleteExamHistory(String id) async {
    await _supabase
        .from('exam_history')
        .update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }

  Future<List<Map<String, dynamic>>> generateExcelData() async {
    try {
      print('Starting Excel data generation...');
      final response = await _supabase
          .from('exam')
          .select('*, course:course_id(*)')
          .order('exam_date', ascending: true);
      print('Generated Excel data for ${response.length} exams');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error generating Excel data: $e');
      rethrow;
    }
  }
}
