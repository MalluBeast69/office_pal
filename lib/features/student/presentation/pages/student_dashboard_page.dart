import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/auth/presentation/pages/login_page.dart';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'dart:async';

class StudentDashboardPage extends ConsumerStatefulWidget {
  final String studentRegNo;
  final String studentName;
  final String departmentId;
  final int semester;

  const StudentDashboardPage({
    super.key,
    required this.studentRegNo,
    required this.studentName,
    required this.departmentId,
    required this.semester,
  });

  @override
  ConsumerState<StudentDashboardPage> createState() =>
      _StudentDashboardPageState();
}

class _StudentDashboardPageState extends ConsumerState<StudentDashboardPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> examSeatingArrangements = [];
  final _scrollController = ScrollController();
  final bool _isLoading = false;
  Map<String, dynamic>? _selectedExam;
  String? _studentRegNo;
  bool _isSeatingVisible = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadStudentInfo();
    _loadSeatingVisibility();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final seatingResponse = await Supabase.instance.client
          .from('seating_arr')
          .select('''
            *,
            exam!inner(
              exam_date,
              session,
              course_id,
              time,
              duration
            ),
            hall:hall_id(*)
          ''')
          .eq('student_reg_no', widget.studentRegNo)
          .order('created_at', ascending: true);

      developer.log('Seating response: $seatingResponse');

      if (mounted) {
        setState(() {
          examSeatingArrangements =
              List<Map<String, dynamic>>.from(seatingResponse);
          isLoading = false;
        });
      }
    } catch (error) {
      developer.log('Error loading student seating data: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading seating data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadStudentInfo() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final studentResponse = await Supabase.instance.client
          .from('student')
          .select()
          .eq('user_id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _studentRegNo = studentResponse['student_reg_no'];
        });
      }
    } catch (error) {
      developer.log('Error loading student info: $error');
    }
  }

  Future<void> _loadSeatingVisibility() async {
    try {
      final response = await Supabase.instance.client
          .from('seating_visibility')
          .select()
          .single();
      if (mounted) {
        setState(() {
          _isSeatingVisible = response['is_visible'] ?? false;
        });
      }
    } catch (error) {
      developer.log('Error loading seating visibility: $error');
      if (mounted) {
        setState(() {
          _isSeatingVisible = false;
        });
      }
    }
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your exam details...',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ).animate().fadeIn(),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadData();
                  await _loadSeatingVisibility();
                  await _loadStudentInfo();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exam details updated'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                color: Theme.of(context).primaryColor,
                backgroundColor: Colors.white,
                strokeWidth: 3,
                displacement: 40,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // App Bar
                    SliverAppBar(
                      expandedHeight: 200,
                      floating: true,
                      pinned: true,
                      stretch: true,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withOpacity(0.8),
                              ],
                            ),
                          ),
                          child: SafeArea(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.white,
                                  child: Text(
                                    widget.studentName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ).animate().scale(),
                                const SizedBox(height: 8),
                                Text(
                                  widget.studentName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.3,
                                      curve: Curves.easeOutQuad,
                                    ),
                                Text(
                                  widget.studentRegNo,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                  ),
                                ).animate().fadeIn().slideY(
                                      begin: 0.3,
                                      curve: Curves.easeOutQuad,
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: _signOut,
                        ),
                      ],
                    ),
                    // Next Exam Countdown
                    if (!isLoading) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _getNextExam() != null
                              ? ExamCountdown(exam: _getNextExam()!)
                              : const Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('No upcoming exams'),
                                  ),
                                ),
                        ),
                      ),
                    ],
                    // Student Info
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.school,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Academic Details',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                InfoRow(
                                  icon: Icons.business,
                                  label: 'Department',
                                  value: widget.departmentId,
                                ),
                                const SizedBox(height: 8),
                                InfoRow(
                                  icon: Icons.timeline,
                                  label: 'Semester',
                                  value: widget.semester.toString(),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn().slideX(),
                      ),
                    ),
                    // Exam Arrangements
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_seat,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Upcoming Exams',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ).animate().fadeIn(),
                      ),
                    ),
                    if (examSeatingArrangements.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_busy,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No exam arrangements yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Pull to refresh when arrangements are made',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ).animate().fadeIn().scale(),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final arrangement = examSeatingArrangements[index];
                            final exam = arrangement['exam'];
                            final examDate = DateTime.parse(exam['exam_date']);
                            final isToday =
                                DateTime.now().difference(examDate).inDays == 0;
                            final isPast = DateTime.now().isAfter(examDate);
                            final hall = arrangement['hall'];

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 8.0,
                              ),
                              child: ExamCard(
                                courseName:
                                    exam['course_id'] ?? 'Unknown Course',
                                courseCode: exam['course_id'] ?? 'N/A',
                                examDate: examDate,
                                session: exam['session'] ?? 'N/A',
                                room: {
                                  'room_name': hall['hall_id'] ?? 'N/A',
                                  'block_name':
                                      'Department: ${hall['hall_dept'] ?? 'N/A'}',
                                  'floor_no': ''
                                },
                                seatNo:
                                    'Seat ${(arrangement['row_no'] * hall['no_of_columns']) + arrangement['column_no'] + 1}',
                                isToday: isToday,
                                isPast: isPast,
                                time: exam['time'],
                                duration: exam['duration'],
                                examData: arrangement,
                                onViewSeating: _showSeatingArrangement,
                                showSeatingDetails: _isSeatingVisible || isPast,
                              ).animate().fadeIn().slideY(
                                    begin: 0.2,
                                    delay: Duration(milliseconds: index * 100),
                                  ),
                            );
                          },
                          childCount: examSeatingArrangements.length,
                        ),
                      ),
                    if (!_isSeatingVisible)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Seating Information',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Seating arrangements will be made visible by the examination department closer to the exam dates. Please check back later.',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam) {
    final DateTime examDate = DateTime.parse(exam['exam_date']);
    final bool isToday = examDate.year == DateTime.now().year &&
        examDate.month == DateTime.now().month &&
        examDate.day == DateTime.now().day;
    final bool isPast = examDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isToday
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam['course_id'],
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, MMMM d').format(examDate),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (_isSeatingVisible || isPast)
                  IconButton(
                    icon: const Icon(Icons.remove_red_eye_outlined),
                    onPressed: () => _showSeatingArrangement(exam),
                    tooltip: 'View Seating Arrangement',
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildExamDetail(
                  icon: exam['session'] == 'FN'
                      ? Icons.wb_sunny
                      : Icons.wb_twilight,
                  label: exam['session'] == 'FN' ? 'Morning' : 'Afternoon',
                  color: exam['session'] == 'FN' ? Colors.blue : Colors.orange,
                ),
                _buildExamDetail(
                  icon: Icons.access_time,
                  label: exam['time'],
                  color: Colors.grey.shade700,
                ),
                _buildExamDetail(
                  icon: Icons.timer,
                  label: '${exam['duration']} mins',
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
          if (!_isSeatingVisible && !isPast)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Seating details will be revealed closer to the exam date',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSeatingArrangement(Map<String, dynamic> arrangement) async {
    final exam = arrangement['exam'];
    final hall = arrangement['hall'];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_seat,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Seat',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            exam['course_id'],
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Teacher's desk
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.brown.shade300,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Teacher\'s Desk',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Seating grid
                        _buildSeatingGrid(
                          hall['no_of_columns'],
                          hall['no_of_rows'],
                          arrangement['row_no'],
                          arrangement['column_no'],
                          exam['session'],
                        ),
                        const SizedBox(height: 16),
                        // Legend
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLegendItem(
                              color: exam['session'] == 'FN'
                                  ? Colors.blue
                                  : Colors.orange,
                              label: 'Your Seat',
                            ),
                            const SizedBox(width: 16),
                            _buildLegendItem(
                              color: Colors.grey.shade300,
                              label: 'Other Seats',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Seat info
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              _buildInfoRow(
                                'Hall',
                                hall['hall_id'],
                                Icons.location_on,
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                'Seat Number',
                                '${(arrangement['row_no'] * hall['no_of_columns']) + arrangement['column_no'] + 1}',
                                Icons.chair,
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                'Time',
                                '${exam['time']} (${exam['duration']} mins)',
                                Icons.access_time,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeatingGrid(
    int columns,
    int rows,
    int studentRow,
    int studentCol,
    String session,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final seatWidth =
            math.min(50.0, (availableWidth - (columns - 1) * 8) / columns);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int row = 0; row < rows; row++) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int col = 0; col < columns; col++) ...[
                    SizedBox(
                      width: seatWidth,
                      child: _buildSeat(
                        row,
                        col,
                        studentRow,
                        studentCol,
                        row * columns + col + 1,
                        session,
                      ),
                    ),
                    if (col < columns - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSeat(
    int row,
    int col,
    int studentRow,
    int studentCol,
    int seatNumber,
    String session,
  ) {
    final bool isStudentSeat = row == studentRow && col == studentCol;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 28,
          decoration: BoxDecoration(
            color: Colors.brown.shade400,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
          ),
          child: Center(
            child: Text(
              seatNumber.toString(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Container(
          height: 18,
          decoration: BoxDecoration(
            color: isStudentSeat
                ? (session == 'FN' ? Colors.blue : Colors.orange)
                : Colors.grey.shade300,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Icon(
            isStudentSeat ? Icons.person : Icons.chair,
            color: isStudentSeat ? Colors.white : Colors.grey.shade400,
            size: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildExamDetail({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color),
        ),
      ],
    );
  }

  Map<String, dynamic>? _getNextExam() {
    if (examSeatingArrangements.isEmpty) return null;

    final now = DateTime.now();
    final futureExams = examSeatingArrangements
        .where((arr) => DateTime.parse(arr['exam']['exam_date']).isAfter(now))
        .toList();

    if (futureExams.isEmpty) return null;

    // Sort by date and return the earliest future exam
    futureExams.sort((a, b) {
      final dateA = DateTime.parse(a['exam']['exam_date']);
      final dateB = DateTime.parse(b['exam']['exam_date']);
      return dateA.compareTo(dateB);
    });

    return futureExams.first['exam'];
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class ExamCard extends StatelessWidget {
  final String courseName;
  final String courseCode;
  final DateTime examDate;
  final String session;
  final Map<String, dynamic> room;
  final String seatNo;
  final bool isToday;
  final bool isPast;
  final String? time;
  final int? duration;
  final Map<String, dynamic> examData;
  final Function(Map<String, dynamic>) onViewSeating;
  final bool showSeatingDetails;

  const ExamCard({
    super.key,
    required this.courseName,
    required this.courseCode,
    required this.examDate,
    required this.session,
    required this.room,
    required this.seatNo,
    required this.isToday,
    required this.isPast,
    required this.examData,
    required this.onViewSeating,
    this.time,
    this.duration,
    this.showSeatingDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isPast
        ? Colors.grey[100]
        : isToday
            ? Colors.green[50]
            : Colors.white;

    return Card(
      elevation: isPast ? 1 : 2,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPast
            ? BorderSide(color: Colors.grey[300]!)
            : isToday
                ? BorderSide(color: Colors.green[300]!)
                : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => ExamDetailsSheet(
              courseName: courseName,
              courseCode: courseCode,
              examDate: examDate,
              session: session,
              room: room,
              seatNo: seatNo,
              time: time,
              duration: duration,
              showSeatingDetails: showSeatingDetails,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courseName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : Colors.black,
                          ),
                        ),
                        Text(
                          courseCode,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showSeatingDetails)
                    IconButton(
                      icon: const Icon(Icons.remove_red_eye_outlined),
                      onPressed: () => onViewSeating(examData),
                      tooltip: 'View Seating Arrangement',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isPast ? Colors.grey : Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('EEE, MMM d').format(examDate),
                    style: TextStyle(
                      fontSize: 14,
                      color: isPast ? Colors.grey : Colors.black87,
                    ),
                  ),
                  if (time != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: isPast ? Colors.grey : Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time!,
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (showSeatingDetails)
                Row(
                  children: [
                    Icon(
                      Icons.room,
                      size: 16,
                      color: isPast ? Colors.grey : Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${room['room_name']} - $seatNo',
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ],
                ),
              if (duration != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: isPast ? Colors.grey : Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$duration mins',
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
              if (isToday)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer,
                        size: 16,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Today\'s Exam',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExamDetailsSheet extends StatelessWidget {
  final String courseName;
  final String courseCode;
  final DateTime examDate;
  final String session;
  final Map<String, dynamic> room;
  final String seatNo;
  final String? time;
  final int? duration;
  final bool showSeatingDetails;

  const ExamDetailsSheet({
    super.key,
    required this.courseName,
    required this.courseCode,
    required this.examDate,
    required this.session,
    required this.room,
    required this.seatNo,
    this.time,
    this.duration,
    this.showSeatingDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            courseName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            courseCode,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          DetailRow(
            icon: Icons.calendar_today,
            label: 'Date',
            value: DateFormat('EEEE, MMMM d, y').format(examDate),
          ),
          const SizedBox(height: 12),
          DetailRow(
            icon: Icons.access_time,
            label: 'Session',
            value: session,
          ),
          if (time != null) ...[
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.schedule,
              label: 'Time',
              value: time!,
            ),
          ],
          if (duration != null) ...[
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.timer_outlined,
              label: 'Duration',
              value: '$duration minutes',
            ),
          ],
          if (showSeatingDetails) ...[
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.location_on,
              label: 'Hall',
              value: room['room_name'],
            ),
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.business,
              label: 'Department',
              value:
                  room['block_name'].toString().replaceAll('Department: ', ''),
            ),
            const SizedBox(height: 12),
            DetailRow(
              icon: Icons.event_seat,
              label: 'Seat',
              value: seatNo,
            ),
          ] else ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Seating details will be revealed closer to the exam date',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }
}

class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ExamCountdown extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ExamCountdown({
    Key? key,
    required this.exam,
  }) : super(key: key);

  @override
  State<ExamCountdown> createState() => _ExamCountdownState();
}

class _ExamCountdownState extends State<ExamCountdown> {
  late Timer _timer;
  late Duration _timeLeft;
  String _tip = '';

  @override
  void initState() {
    super.initState();
    _updateTimeLeft();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTimeLeft());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTimeLeft() {
    final examDate = DateTime.parse(widget.exam['exam_date']);
    final now = DateTime.now();
    setState(() {
      _timeLeft = examDate.difference(now);
      _updateTip();
    });
  }

  void _updateTip() {
    final daysLeft = _timeLeft.inDays;
    if (daysLeft > 7) {
      _tip =
          'Start preparing early for ${widget.exam['course_id']}. Create a study schedule.';
    } else if (daysLeft > 3) {
      _tip =
          'Review your notes and practice problems for ${widget.exam['course_id']}.';
    } else if (daysLeft > 1) {
      _tip =
          'Get enough rest and do final revisions for ${widget.exam['course_id']}.';
    } else if (daysLeft > 0) {
      _tip = 'Prepare your hall ticket and materials for tomorrow\'s exam.';
    } else if (_timeLeft.inHours > 1) {
      _tip = 'Get ready! Arrive at the exam hall at least 30 minutes early.';
    } else {
      _tip = 'Your exam is about to start. Good luck!';
    }
  }

  Color _getColor() {
    final daysLeft = _timeLeft.inDays;
    if (daysLeft > 7) {
      return Colors.blue;
    } else if (daysLeft > 3) {
      return Colors.green;
    } else if (daysLeft > 1) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  String _formatDuration() {
    if (_timeLeft.inDays > 0) {
      return '${_timeLeft.inDays} days';
    } else if (_timeLeft.inHours > 0) {
      return '${_timeLeft.inHours} hours';
    } else if (_timeLeft.inMinutes > 0) {
      return '${_timeLeft.inMinutes} minutes';
    } else {
      return '${_timeLeft.inSeconds} seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.5), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer, color: color),
                const SizedBox(width: 8),
                Text(
                  'Next Exam Countdown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.exam['course_id'],
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Date: ${DateFormat('EEEE, MMMM d').format(DateTime.parse(widget.exam['exam_date']))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'Time: ${widget.exam['time']} (${widget.exam['session'] == 'FN' ? 'Morning' : 'Afternoon'})',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    ' remaining',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tip,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.3);
  }
}
