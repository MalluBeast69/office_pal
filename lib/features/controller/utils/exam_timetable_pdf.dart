import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:office_pal/features/controller/domain/models/course.dart';
import 'package:office_pal/features/controller/domain/models/exam.dart';

class ExamTimetablePDF {
  static Future<List<int>> generate(
      List<Exam> exams, List<Course> courses) async {
    final pdf = pw.Document();

    // Sort exams by date and time
    exams.sort((a, b) {
      final dateCompare = a.examDate.compareTo(b.examDate);
      if (dateCompare != 0) return dateCompare;
      return a.time.compareTo(b.time);
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _buildHeader(),
          pw.SizedBox(height: 20),
          _buildTimetable(exams, courses),
        ],
        footer: (context) => _buildFooter(context),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'EXAM TIMETABLE',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          DateFormat('MMMM yyyy').format(DateTime.now()),
          style: const pw.TextStyle(
            fontSize: 16,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildTimetable(List<Exam> exams, List<Course> courses) {
    return pw.Table.fromTextArray(
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blue,
      ),
      cellHeight: 40,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
      },
      headers: ['Date', 'Course', 'Session', 'Time', 'Duration'],
      data: exams.map((exam) {
        final course = courses.firstWhere((c) => c.courseCode == exam.courseId);
        return [
          DateFormat('MMM d, y').format(exam.examDate),
          '${course.courseCode}\n${course.courseName}',
          exam.session,
          exam.time,
          '${exam.duration} mins',
        ];
      }).toList(),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 1)),
      ),
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated on ${DateFormat('MMM d, y HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
