import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';

class CourseRepository {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getCourses() async {
    try {
      final response = await _supabase
          .from('course')
          .select()
          .order('course_code', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch courses: $e');
    }
  }

  Future<Course> getCourseByCode(String courseCode) async {
    try {
      final response = await _supabase
          .from('course')
          .select()
          .eq('course_code', courseCode)
          .single();

      return Course.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch course: $e');
    }
  }
}
