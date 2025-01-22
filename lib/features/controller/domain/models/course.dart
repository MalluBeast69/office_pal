class Course {
  final String courseCode;
  final String courseName;
  final String deptId;
  final int credit;
  final String courseType;
  final int semester;

  Course({
    required this.courseCode,
    required this.courseName,
    required this.deptId,
    required this.credit,
    required this.courseType,
    required this.semester,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    try {
      print('Creating Course from JSON: $json'); // Debug print
      return Course(
        courseCode: json['course_code'] as String,
        courseName: json['course_name'] as String,
        deptId: json['dept_id'] as String,
        credit: json['credit'] as int,
        courseType: json['course_type'] as String,
        semester: json['semester'] as int,
      );
    } catch (e) {
      print('Error creating Course from JSON: $e'); // Debug print
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        'course_code': courseCode,
        'course_name': courseName,
        'dept_id': deptId,
        'credit': credit,
        'course_type': courseType,
        'semester': semester,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Course &&
          runtimeType == other.runtimeType &&
          courseCode == other.courseCode;

  @override
  int get hashCode => courseCode.hashCode;

  @override
  String toString() =>
      'Course{courseCode: $courseCode, courseName: $courseName, courseType: $courseType}';
}
