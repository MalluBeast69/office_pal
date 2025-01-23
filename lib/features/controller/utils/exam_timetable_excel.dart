import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamTimetableExcel {
  static List<int> generate(List<Exam> exams, List<Course> courses) {
    final excel = Excel.createExcel();
    final sheet = excel.sheets[excel.getDefaultSheet()!]!;

    // Add headers
    final headers = [
      'Date',
      'Session',
      'Time',
      'Course Code',
      'Course Name',
      'Department',
      'Duration (mins)'
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
      );
    }

    // Sort exams by date and session
    exams.sort((a, b) {
      final dateCompare = a.examDate.compareTo(b.examDate);
      if (dateCompare != 0) return dateCompare;
      return a.session.compareTo(b.session);
    });

    // Add exam data
    for (var i = 0; i < exams.length; i++) {
      final exam = exams[i];
      final course = courses.firstWhere((c) => c.courseCode == exam.courseId);
      final rowData = [
        DateFormat('MMM d, y').format(exam.examDate),
        exam.session,
        exam.time,
        course.courseCode,
        course.courseName,
        course.deptId,
        exam.duration.toString(),
      ];

      for (var j = 0; j < rowData.length; j++) {
        final cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = TextCellValue(rowData[j]);
      }
    }

    // Auto-fit columns
    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 15.0);
    }
    sheet.setColumnWidth(4, 30.0); // Make course name column wider

    return excel.encode()!;
  }

  static List<int> generateByDateAndSession(
    List<Exam> exams,
    List<Course> courses,
    DateTime date,
    String session,
  ) {
    final filteredExams = exams.where((exam) {
      return exam.examDate.year == date.year &&
          exam.examDate.month == date.month &&
          exam.examDate.day == date.day &&
          exam.session.toUpperCase() == session.toUpperCase();
    }).toList();

    return generate(filteredExams, courses);
  }
}
