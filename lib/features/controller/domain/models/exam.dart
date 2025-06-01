class Exam {
  final String examId;
  final String courseId;
  final DateTime examDate;
  final String session;
  final String time;
  final int duration;
  final DateTime createdAt;
  final DateTime updatedAt;

  Exam({
    required this.examId,
    required this.courseId,
    required this.examDate,
    required this.session,
    required this.time,
    required this.duration,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      examId: json['exam_id'] as String,
      courseId: json['course_id'] as String,
      examDate: DateTime.parse(json['exam_date'] as String),
      session: json['session'] as String,
      time: json['time'] as String,
      duration: json['duration'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'exam_id': examId,
        'course_id': courseId,
        'exam_date': examDate.toIso8601String().split('T')[0],
        'session': session,
        'time': time,
        'duration': duration,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  String toString() =>
      'Exam{examId: $examId, courseId: $courseId, examDate: $examDate, session: $session, time: $time, duration: $duration}';
}
