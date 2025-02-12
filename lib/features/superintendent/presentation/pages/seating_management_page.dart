import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math' as math;
import 'seating_arrangement/select_exam_page.dart';
import 'dart:developer' as developer;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

class SeatingManagementPage extends ConsumerStatefulWidget {
  const SeatingManagementPage({Key? key}) : super(key: key);

  static const String routeName = '/seating_management';

  @override
  ConsumerState<SeatingManagementPage> createState() =>
      _SeatingManagementPageState();
}

class _SeatingManagementPageState extends ConsumerState<SeatingManagementPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  bool _isCalendarVisible = false;
  final DateTime _focusedDay = DateTime.now();
  DateTime? _selectedStartDate;
  String? _selectedSession;
  Map<String, Map<String, List<Map<String, dynamic>>>> _filteredArrangements =
      {};
  List<Map<String, dynamic>> _halls = [];
  Map<String, Map<String, List<Map<String, dynamic>>>> _seatingArrangements =
      {};
  String? _selectedHall;
  DateTime? _selectedDate;
  bool _showOnlyHallsWithExams = false;
  bool _isSeatingGridExpanded = true;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String? _selectedExam;
  bool _isSeatingVisible = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSeatingVisibility();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // Load halls
      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true);
      _halls = List<Map<String, dynamic>>.from(hallsResponse);

      // Load seating arrangements
      final response =
          await Supabase.instance.client.from('seating_arr').select('''
            *,
            exam:exam_id(*,
              course:course_id(
                course_name
              )
            ),
            hall:hall_id(*)
          ''').order('created_at');

      final arrangements = List<Map<String, dynamic>>.from(response);

      // Process arrangements to include course names
      for (var arrangement in arrangements) {
        if (arrangement['exam'] != null &&
            arrangement['exam']['course'] != null) {
          arrangement['exam']['course_name'] =
              arrangement['exam']['course']['course_name'] ?? 'Unknown Course';
        }
      }

      _groupArrangements(arrangements);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error) {
      developer.log('Error loading data: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _groupArrangements(List<Map<String, dynamic>> arrangements) {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final arrangement in arrangements) {
      final hallId = arrangement['hall_id'];
      final exam = arrangement['exam'];
      final date = exam['exam_date'].toString().split(' ')[0];
      final session = _normalizeSession(exam['session']);

      grouped[hallId] ??= {};
      grouped[hallId]![date] ??= [];
      grouped[hallId]![date]!.add(arrangement);
    }

    setState(() {
      _seatingArrangements = grouped;
    });
  }

  void _applyFilters() {
    // Apply date filter
    if (_selectedStartDate != null) {
      _filteredArrangements = Map.from(_filteredArrangements)
        ..removeWhere((date, _) {
          final examDate = DateTime.parse(date);
          return examDate.isBefore(_selectedStartDate!);
        });
    }

    // Apply session filter
    if (_selectedSession != null) {
      final normalizedSelectedSession = _normalizeSession(_selectedSession!);
      _filteredArrangements = Map.from(_filteredArrangements)
        ..forEach((date, sessions) {
          sessions.removeWhere((session, _) =>
              _normalizeSession(session) != normalizedSelectedSession);
        })
        ..removeWhere((_, sessions) => sessions.isEmpty);
    }

    // Apply search filter
    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      _filteredArrangements = Map.from(_filteredArrangements)
        ..forEach((date, sessions) {
          sessions.forEach((session, arrangements) {
            arrangements.removeWhere((arrangement) {
              final exam = arrangement['exam'];
              return !exam['course_id']
                      .toString()
                      .toLowerCase()
                      .contains(searchQuery) &&
                  !arrangement['student_reg_no']
                      .toString()
                      .toLowerCase()
                      .contains(searchQuery) &&
                  !arrangement['hall_id']
                      .toString()
                      .toLowerCase()
                      .contains(searchQuery);
            });
          });
        })
        ..removeWhere((_, sessions) {
          sessions.removeWhere((_, arrangements) => arrangements.isEmpty);
          return sessions.isEmpty;
        });
    }

    setState(() {});
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedStartDate = null;
      _selectedSession = null;
      _isCalendarVisible = false;
    });
    _loadData();
  }

  Future<void> _deleteSeatingArrangement(String examId) async {
    try {
      setState(() => _isLoading = true);

      await Supabase.instance.client
          .from('seating_arr')
          .delete()
          .eq('exam_id', examId);

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seating arrangement deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      developer.log('Error deleting seating arrangement: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting seating arrangement: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _viewSeatingArrangement(Map<String, dynamic> arrangement) async {
    try {
      setState(() => _isLoading = true);

      // Fetch student details including department
      final studentResponse = await Supabase.instance.client
          .from('student')
          .select('*, department:dept_id(*)')
          .eq('student_reg_no', arrangement['student_reg_no'])
          .single();

      if (!mounted) return;
      setState(() => _isLoading = false);

      final exam = arrangement['exam'];
      final seatNumber =
          arrangement['row_no'] * arrangement['hall']['no_of_columns'] +
              arrangement['column_no'] +
              1;
      final studentData = studentResponse as Map<String, dynamic>;
      final departmentData = studentData['department'] as Map<String, dynamic>;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Student ${arrangement['student_reg_no']}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Name',
                    studentData['student_name']?.toString() ?? 'Not specified'),
                _buildDetailRow('Department',
                    departmentData['dept_name']?.toString() ?? 'Not specified'),
                _buildDetailRow('Semester',
                    studentData['semester']?.toString() ?? 'Not specified'),
                const Divider(),
                _buildDetailRow('Course', exam['course_id']),
                _buildDetailRow(
                    'Date',
                    DateFormat('EEEE, MMMM d, y')
                        .format(DateTime.parse(exam['exam_date']))),
                _buildDetailRow(
                    'Session', _getSessionDisplayName(exam['session'])),
                _buildDetailRow('Time', exam['time']),
                _buildDetailRow('Duration', '${exam['duration']} minutes'),
                _buildDetailRow('Hall', arrangement['hall_id']),
                _buildDetailRow('Seat Number', seatNumber.toString()),
                _buildDetailRow('Faculty', arrangement['faculty_id']),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log('Error fetching student details: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching student details: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _editSeatingArrangement(Map<String, dynamic> arrangement) async {
    try {
      setState(() => _isLoading = true);

      // Get available halls
      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true);

      if (!mounted) return;
      setState(() => _isLoading = false);

      final halls = List<Map<String, dynamic>>.from(hallsResponse);

      // Show edit dialog
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _EditSeatingDialog(
          arrangement: arrangement,
          availableHalls: halls,
        ),
      );

      if (result != null) {
        setState(() => _isLoading = true);

        // Update seating arrangement
        await Supabase.instance.client.from('seating_arr').update({
          'hall_id': result['hall_id'],
          'column_no': result['column_no'],
          'row_no': result['row_no'],
        }).eq('arrangement_id', arrangement['arrangement_id']);

        await _loadData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seating arrangement updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      developer.log('Error updating seating arrangement: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating seating arrangement: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Generate Seating'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SelectExamPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          FilterChip(
            label: const Text('Show Halls with Exams'),
            selected: _showOnlyHallsWithExams,
            onSelected: (value) {
              setState(() {
                _showOnlyHallsWithExams = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHallGrid() {
    final filteredHalls = _showOnlyHallsWithExams
        ? _halls
            .where((hall) => _seatingArrangements.containsKey(hall['hall_id']))
            .toList()
        : _halls;

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filteredHalls.length,
            itemBuilder: (context, index) {
              final hall = filteredHalls[index];
              final hallId = hall['hall_id'];
              final isSelected = _selectedHall == hallId;
              final hasArrangements = _seatingArrangements.containsKey(hallId);
              final examCount = hasArrangements
                  ? _seatingArrangements[hallId]!
                      .values
                      .expand((arrangements) => arrangements)
                      .length
                  : 0;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedHall = isSelected ? null : hallId;
                    _selectedDate = null;
                    _selectedSession = null;
                  });
                },
                child: Card(
                  elevation: isSelected ? 8 : 2,
                  color: isSelected
                      ? Theme.of(context).primaryColor.withOpacity(0.1)
                      : null,
                  child: Stack(
                    children: [
                      if (hasArrangements)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$examCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              hallId,
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Capacity: ${hall['capacity']}',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeatingDetails() {
    if (_selectedHall == null) {
      return const Center(
        child: Text('Select a hall to view seating arrangements'),
      );
    }

    final hallArrangements = _seatingArrangements[_selectedHall];
    if (hallArrangements == null || hallArrangements.isEmpty) {
      return const Center(
        child: Text('No seating arrangements found for this hall'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Hall $_selectedHall',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (_selectedDate == null)
          _buildDateSelection(hallArrangements)
        else if (_selectedSession == null)
          _buildSessionSelection(
              hallArrangements[_selectedDate!.toString().split(' ')[0]]!)
        else
          Expanded(
            child: _buildVisualLayout(hallArrangements),
          ),
      ],
    );
  }

  Widget _buildDateSelection(
      Map<String, List<Map<String, dynamic>>> arrangements) {
    final dates = arrangements.keys.toList()
      ..sort((a, b) => DateTime.parse(a).compareTo(DateTime.parse(b)));

    // Filter dates based on selected date range
    final filteredDates = dates.where((date) {
      final examDate = DateTime.parse(date);
      if (_filterStartDate != null && examDate.isBefore(_filterStartDate!)) {
        return false;
      }
      if (_filterEndDate != null && examDate.isAfter(_filterEndDate!)) {
        return false;
      }
      return true;
    }).toList();

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today),
                const SizedBox(width: 8),
                Text(
                  'Select Date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.filter_alt),
                  label: Text(_filterStartDate == null
                      ? 'Filter Dates'
                      : '${DateFormat('MMM d').format(_filterStartDate!)} - ${_filterEndDate != null ? DateFormat('MMM d').format(_filterEndDate!) : 'Now'}'),
                  onPressed: () => _showDateFilterDialog(),
                ),
              ],
            ),
          ),
          if (_filterStartDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Chip(
                    label: Text(
                      'Filtered: ${filteredDates.length} of ${dates.length} dates',
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _filterStartDate = null;
                        _filterEndDate = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: filteredDates.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No exams found in selected date range',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredDates.length,
                    itemBuilder: (context, index) {
                      final date = filteredDates[index];
                      final dateArrangements = arrangements[date]!;
                      final formattedDate = DateFormat('EEEE, MMMM d, y')
                          .format(DateTime.parse(date));

                      // Calculate sessions and students info
                      final sessions = <String>{};
                      var totalStudents = 0;
                      for (var arr in dateArrangements) {
                        sessions.add(arr['exam']['session']);
                        totalStudents++;
                      }
                      final hasMorning = sessions.contains('FN');
                      final hasAfternoon = sessions.contains('AN');

                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Stack(
                              children: [
                                if (hasMorning)
                                  const Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Icon(
                                      Icons.wb_sunny,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                  ),
                                if (hasAfternoon)
                                  const Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Icon(
                                      Icons.wb_twilight,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          title: Text(formattedDate),
                          subtitle: Text(
                            '${sessions.length} ${sessions.length == 1 ? 'Session' : 'Sessions'} • $totalStudents ${totalStudents == 1 ? 'Student' : 'Students'}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedDate = DateTime.parse(date);
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionSelection(List<Map<String, dynamic>> arrangements) {
    final sessions = arrangements
        .map((arr) => arr['exam']['session'] as String)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Session',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sessions.map((session) {
            final normalizedSession = _normalizeSession(session);
            return ChoiceChip(
              selected: _selectedSession == session,
              label: Text(_getSessionDisplayName(session)),
              avatar: Icon(
                normalizedSession == 'MORNING'
                    ? Icons.wb_sunny
                    : Icons.wb_twilight,
                size: 18,
              ),
              onSelected: (_) {
                setState(() {
                  _selectedSession = session;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVisualLayout(
      Map<String, List<Map<String, dynamic>>> arrangements) {
    final selectedHallData = _halls.firstWhere(
      (hall) => hall['hall_id'] == _selectedHall,
      orElse: () => {'no_of_columns': 0, 'no_of_rows': 0},
    );

    if (_selectedDate == null || _selectedSession == null) {
      return const Center(
        child: Text('Please select a date and session'),
      );
    }

    final dateStr = _selectedDate!.toString().split(' ')[0];
    final dateArrangements = arrangements[dateStr];

    if (dateArrangements == null) {
      return const Center(
        child: Text('No arrangements found for selected date'),
      );
    }

    final sessionArrangements = dateArrangements
        .where((arr) => arr['exam']['session'] == _selectedSession)
        .toList();

    if (sessionArrangements.isEmpty) {
      return const Center(
        child: Text('No arrangements found for selected session'),
      );
    }

    // Get unique exams in current seating
    final examMap = <String, Map<String, String>>{};
    for (final arrangement in sessionArrangements) {
      final exam = arrangement['exam'];
      final courseId = exam['course_id'];
      if (!examMap.containsKey(courseId)) {
        examMap[courseId] = {
          'course_code': courseId,
          'course_name': exam['course_name'] ?? 'Unknown Course',
        };
      }
    }
    final exams = examMap.values.toList();

    // Calculate statistics with null safety
    final totalStudents = sessionArrangements.length;
    final regularStudents =
        sessionArrangements.where((s) => s['is_supplementary'] == false).length;
    final supplementaryStudents =
        sessionArrangements.where((s) => s['is_supplementary'] == true).length;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                DateFormat('MMM d').format(_selectedDate!),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 16),
              CircleAvatar(
                backgroundColor:
                    _normalizeSession(_selectedSession!) == 'MORNING'
                        ? Colors.blue
                        : Colors.orange,
                radius: 16,
                child: Text(
                  _getSessionDisplayName(_selectedSession!),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(_isSeatingGridExpanded
                    ? Icons.unfold_less
                    : Icons.unfold_more),
                onPressed: () {
                  setState(() {
                    _isSeatingGridExpanded = !_isSeatingGridExpanded;
                  });
                },
                tooltip: _isSeatingGridExpanded
                    ? 'Collapse seating grid'
                    : 'Expand seating grid',
              ),
              TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                onPressed: () {
                  setState(() {
                    _selectedSession = null;
                  });
                },
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seating Grid
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: _buildSeatingGrid(
                    selectedHallData['no_of_columns'],
                    selectedHallData['no_of_rows'],
                    {dateStr: sessionArrangements},
                  ),
                ),
              ),
              // Exam Filter Panel
              SizedBox(
                width: 250,
                child: Card(
                  margin: const EdgeInsets.only(left: 16, right: 16),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Filter by Exam',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                selected: _selectedExam == null,
                                showCheckmark: false,
                                label: const Text('All Exams'),
                                onSelected: (_) {
                                  setState(() => _selectedExam = null);
                                },
                              ),
                              ...exams.map((exam) => FilterChip(
                                    selected:
                                        _selectedExam == exam['course_code'],
                                    showCheckmark: false,
                                    label: Text(
                                      '${exam['course_code']} - ${exam['course_name']}',
                                      style: TextStyle(
                                        fontSize: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .fontSize,
                                      ),
                                    ),
                                    onSelected: (_) {
                                      setState(() => _selectedExam =
                                          exam['course_code'] as String);
                                    },
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Add this helper method for statistics in the filter panel
  Widget _buildStatisticRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildSeatingGrid(int columns, int rows,
      Map<String, List<Map<String, dynamic>>> arrangements) {
    final allArrangements = arrangements.values.expand((list) => list).toList();
    final firstArrangement =
        allArrangements.isNotEmpty ? allArrangements.first : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final seatWidth =
            math.min(80.0, (availableWidth - (columns - 1) * 16) / columns);

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Teacher's desk at the top
              InkWell(
                onTap: firstArrangement != null
                    ? () => _showTeacherInfo(firstArrangement)
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: const BoxConstraints(
                    minWidth: 160,
                    minHeight: 48,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.brown.shade300,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Teacher\'s Desk',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tap to view details',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Student seating grid
              for (int row = 0; row < rows; row++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int col = 0; col < columns; col++) ...[
                      SizedBox(
                        width: seatWidth,
                        child: _buildSeat(row, col, allArrangements),
                      ),
                      if (col < columns - 1) const SizedBox(width: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeat(int row, int col, List<Map<String, dynamic>> arrangements) {
    final arrangement = arrangements.firstWhere(
      (arr) => arr['row_no'] == row && arr['column_no'] == col,
      orElse: () => {},
    );
    final bool isOccupied = arrangement.isNotEmpty;
    final exam = isOccupied ? arrangement['exam'] : null;
    final isHighlighted = _selectedExam == null ||
        (isOccupied && exam['course_id'] == _selectedExam);

    // Calculate sequential seat number
    final seatNumber =
        (row * arrangements.first['hall']['no_of_columns'] + col + 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isOccupied ? () => _viewSeatingArrangement(arrangement) : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: isHighlighted ? 1.0 : 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Desk
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.brown.shade400,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Always show seat number
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Text(
                        '$seatNumber',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isOccupied)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            arrangement['student_reg_no']
                                .toString()
                                .substring(0, 4),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Student icon
              Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isOccupied
                      ? (exam['session'] == 'FN' ? Colors.blue : Colors.orange)
                      : Colors.grey.shade300,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Icon(
                  isOccupied ? Icons.school : Icons.chair,
                  color: isOccupied ? Colors.white : Colors.grey.shade400,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArrangementDetails(
      Map<String, List<Map<String, dynamic>>> arrangements) {
    final dates = arrangements.keys.toList()
      ..sort((a, b) => DateTime.parse(a).compareTo(DateTime.parse(b)));

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.menu_book),
                const SizedBox(width: 8),
                Text(
                  'Courses & Students',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: dates.length,
              itemBuilder: (context, index) {
                final date = dates[index];
                final dateArrangements = arrangements[date]!;

                // Group arrangements by course
                final courseGroups = <String, List<Map<String, dynamic>>>{};
                for (var arr in dateArrangements) {
                  final courseId = arr['exam']['course_id'];
                  courseGroups[courseId] ??= [];
                  courseGroups[courseId]!.add(arr);
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEEE, MMMM d')
                                  .format(DateTime.parse(date)),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: courseGroups.length,
                        itemBuilder: (context, courseIndex) {
                          final courseId =
                              courseGroups.keys.elementAt(courseIndex);
                          final courseArrangements = courseGroups[courseId]!
                            ..sort((a, b) {
                              final aNumber =
                                  a['row_no'] * a['hall']['no_of_columns'] +
                                      a['column_no'] +
                                      1;
                              final bNumber =
                                  b['row_no'] * b['hall']['no_of_columns'] +
                                      b['column_no'] +
                                      1;
                              return aNumber.compareTo(bNumber);
                            });
                          final exam = courseArrangements.first['exam'];
                          final studentCount = courseArrangements.length;

                          return ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: exam['session'] == 'FN'
                                  ? Colors.blue
                                  : Colors.orange,
                              child: Icon(
                                exam['session'] == 'FN'
                                    ? Icons.wb_sunny
                                    : Icons.wb_twilight,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(courseId),
                            subtitle: Text(
                              '${exam['time']} | $studentCount students',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                color: Colors.grey.shade50,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Duration: ${exam['duration']} minutes'),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Students:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: courseArrangements.map((arr) {
                                        final seatNumber = arr['row_no'] *
                                                arr['hall']['no_of_columns'] +
                                            arr['column_no'] +
                                            1;
                                        return Chip(
                                          label: Text(
                                            '${arr['student_reg_no']} (Seat $seatNumber)',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                          backgroundColor: Colors.white,
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon:
                                              const Icon(Icons.edit, size: 18),
                                          label: const Text('Edit'),
                                          onPressed: () =>
                                              _editSeatingArrangement(
                                                  courseArrangements.first),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete,
                                              size: 18),
                                          label: const Text('Delete'),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.red),
                                          onPressed: () =>
                                              _showDeleteConfirmation(
                                                  exam['exam_id']),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seating Management'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(
                _isSeatingVisible ? Icons.visibility : Icons.visibility_off,
                color: _isSeatingVisible ? Colors.green : Colors.red,
              ),
              tooltip: _isSeatingVisible
                  ? 'Seating is visible to students'
                  : 'Seating is hidden from students',
              onPressed: _toggleSeatingVisibility,
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Download PDF',
              onPressed: _generateAndDownloadPDF,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Arrangements',
            onPressed: _showDeleteOptions,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create New Arrangement',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SelectExamPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTopBar(),
                if (_seatingArrangements.isEmpty)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Don't see any exams? Try refreshing the page or check if seating arrangements have been generated.",
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          onPressed: _loadData,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildHallGrid(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 3,
                        child: _buildSeatingDetails(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showDeleteConfirmation(String examId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Seating Arrangement'),
        content: const Text(
            'Are you sure you want to delete this seating arrangement?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSeatingArrangement(examId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showTeacherInfo(Map<String, dynamic> arrangement) async {
    try {
      setState(() => _isLoading = true);

      // Check if faculty_id exists
      final facultyId = arrangement['faculty_id'];
      if (facultyId == null) {
        throw Exception('No faculty assigned');
      }

      // Fetch faculty details
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .eq('faculty_id', facultyId)
          .single();

      if (!mounted) return;
      setState(() => _isLoading = false);

      final facultyData = facultyResponse as Map<String, dynamic>;
      final exam = arrangement['exam'] as Map<String, dynamic>? ?? {};

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.brown.shade300,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Text('Assigned Teacher'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Name',
                  facultyData['faculty_name']?.toString() ?? 'Not specified'),
              _buildDetailRow('Faculty ID',
                  facultyData['faculty_id']?.toString() ?? 'Not specified'),
              _buildDetailRow('Department',
                  facultyData['dept_id']?.toString() ?? 'Not specified'),
              const Divider(),
              _buildDetailRow(
                  'Course', exam['course_id']?.toString() ?? 'Not specified'),
              _buildDetailRow(
                'Session',
                _getSessionDisplayName(exam['session']),
              ),
              _buildDetailRow(
                  'Time', exam['time']?.toString() ?? 'Not specified'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log('Error fetching faculty details: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching faculty details: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDateFilterDialog() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => _DateFilterDialog(
        initialStartDate: _filterStartDate,
        initialEndDate: _filterEndDate,
      ),
    );

    if (result != null) {
      setState(() {
        _filterStartDate = result['start'];
        _filterEndDate = result['end'];
      });
    }
  }

  Future<void> _deleteSeatingArrangementsByDate(DateTime date) async {
    try {
      setState(() => _isLoading = true);

      // Format date to match the database format
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);

      // Get exam IDs for the selected date
      final examIds = _seatingArrangements[formattedDate]
              ?.values
              .expand((e) => e)
              .map((e) => e['exam_id'])
              .where((id) => id != null) // Filter out null IDs
              .toList() ??
          [];

      if (examIds.isEmpty) {
        throw Exception('No seating arrangements found for selected date');
      }

      // Delete arrangements for these exam IDs
      await Supabase.instance.client
          .from('seating_arr')
          .delete()
          .in_('exam_id', examIds);

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seating arrangements deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      developer.log('Error deleting seating arrangements: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting seating arrangements: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteAllSeatingArrangements() async {
    try {
      setState(() => _isLoading = true);

      // Delete all records with a valid WHERE clause
      await Supabase.instance.client.from('seating_arr').delete().gte(
          'created_at',
          DateTime(2020)
              .toIso8601String()); // This will match all records since 2020

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All seating arrangements deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      developer.log('Error deleting all seating arrangements: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting all seating arrangements: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showDeleteOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Seating Arrangements'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: const Text('Delete by Date'),
              subtitle:
                  const Text('Delete all arrangements for a specific date'),
              onTap: () {
                Navigator.pop(context);
                _showDatePicker();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.domain, color: Colors.green),
              title: const Text('Delete by Hall'),
              subtitle:
                  const Text('Delete all arrangements for a specific hall'),
              onTap: () {
                Navigator.pop(context);
                _showHallSelectionDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete All'),
              subtitle: const Text('Delete all seating arrangements'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteAllConfirmation();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDatePicker() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null && mounted) {
      _showDeleteDateConfirmation(pickedDate);
    }
  }

  void _showDeleteDateConfirmation(DateTime date) {
    final formattedDate = DateFormat('MMMM d, yyyy').format(date);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text(
            'Are you sure you want to delete all seating arrangements for $formattedDate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSeatingArrangementsByDate(date);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete All'),
        content: const Text(
            'Are you sure you want to delete ALL seating arrangements? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAllSeatingArrangements();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndDownloadPDF() async {
    try {
      setState(() => _isLoading = true);

      // Create PDF document
      final pdf = pw.Document();

      // Define consistent cell size and styling
      final headerStyle = pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      );
      const normalStyle = pw.TextStyle(fontSize: 9);
      const smallStyle = pw.TextStyle(fontSize: 7);

      // Group arrangements by date and session
      final arrangementsByDateAndSession =
          <String, Map<String, Map<String, List<Map<String, dynamic>>>>>{};

      for (final hallId in _seatingArrangements.keys) {
        final hallArrangements = _seatingArrangements[hallId]!;

        for (final date in hallArrangements.keys) {
          arrangementsByDateAndSession[date] ??= {};
          final arrangements = hallArrangements[date]!;

          // Group arrangements by session and hall
          for (final arr in arrangements) {
            final session = arr['exam']['session'] as String;
            arrangementsByDateAndSession[date]![session] ??= {};
            arrangementsByDateAndSession[date]![session]![hallId] ??= [];
            arrangementsByDateAndSession[date]![session]![hallId]!.add(arr);
          }
        }
      }

      // Process each date and session
      for (final date in arrangementsByDateAndSession.keys) {
        final sessions = arrangementsByDateAndSession[date]!;

        for (final session in sessions.keys) {
          final halls = sessions[session]!;
          if (halls.isEmpty) continue;

          // Get all unique exams for this session
          final examsInSession = halls.values
              .expand((students) => students)
              .map((arr) => arr['exam'])
              .toSet()
              .toList();

          if (examsInSession.isEmpty) continue;

          // Sort exams by course ID for consistent display
          examsInSession.sort((a, b) =>
              (a['course_id'] as String).compareTo(b['course_id'] as String));

          // Add page for this date and session (containing all halls)
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (context) {
                final pages = <pw.Widget>[];

                // Header section
                pages.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 1),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Examination Seating Arrangement',
                          style: headerStyle,
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Date: ${DateFormat('MMMM d, y').format(DateTime.parse(date))}',
                          style: normalStyle,
                        ),
                        pw.Text(
                          'Session: ${_getSessionDisplayName(session)}',
                          style: normalStyle,
                        ),
                        pw.Text(
                          'Time: ${examsInSession.first['time']}',
                          style: normalStyle,
                        ),
                      ],
                    ),
                  ),
                );

                pages.add(pw.SizedBox(height: 16));

                // Process each hall vertically
                for (final hallId in halls.keys) {
                  final students = halls[hallId]!;
                  final hall = _halls.firstWhere(
                    (h) => h['hall_id'] == hallId,
                    orElse: () => throw Exception('Hall $hallId not found'),
                  );
                  final rows = hall['no_of_rows'] as int;
                  final cols = hall['no_of_columns'] as int;

                  // Calculate optimal cell dimensions
                  final pageWidth = PdfPageFormat.a4.availableWidth - 40;
                  final cellWidth = pageWidth / cols;
                  final cellHeight =
                      math.min(30.0, 400 / rows); // Compact layout
                  final double cellPadding = cellWidth < 30 ? 2.0 : 4.0;

                  // Hall header
                  pages.add(
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      color: PdfColors.grey200,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text('Hall: ${hall['hall_id']}',
                              style: headerStyle),
                        ],
                      ),
                    ),
                  );

                  pages.add(pw.SizedBox(height: 8));

                  // Create seating grid
                  final tableRows = List<pw.TableRow>.generate(rows, (row) {
                    return pw.TableRow(
                      children: List<pw.Widget>.generate(cols, (col) {
                        final student = students.firstWhere(
                          (arr) =>
                              arr['row_no'] == row && arr['column_no'] == col,
                          orElse: () => <String, dynamic>{},
                        );
                        final seatNumber = row * cols + col + 1;

                        return pw.Container(
                          height: cellHeight,
                          width: cellWidth,
                          padding: pw.EdgeInsets.all(cellPadding),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 0.5),
                          ),
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                'S$seatNumber',
                                style: smallStyle,
                                textAlign: pw.TextAlign.center,
                              ),
                              if (student.isNotEmpty) ...[
                                pw.SizedBox(height: cellHeight > 20 ? 2 : 1),
                                pw.Text(
                                  student['student_reg_no'].toString(),
                                  style: normalStyle,
                                  textAlign: pw.TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    );
                  });

                  pages.add(
                    pw.Container(
                      width: pageWidth,
                      child: pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultColumnWidth: pw.FixedColumnWidth(cellWidth),
                        children: tableRows,
                      ),
                    ),
                  );

                  pages.add(pw.SizedBox(height: 16));
                }

                return pages;
              },
            ),
          );
        }
      }

      // Save PDF and handle download based on platform
      final bytes = await pdf.save();

      if (kIsWeb) {
        // Web platform: Use blob and download
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download =
              'seating_arrangements_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile/Desktop platforms: Use path_provider
        final output = await getTemporaryDirectory();
        final file = File(
            '${output.path}/seating_arrangements_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf');
        await file.writeAsBytes(bytes);

        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          throw 'Could not open the PDF file';
        }
      }

      setState(() => _isLoading = false);
    } catch (error) {
      developer.log('Error generating PDF: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showHallSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Hall'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _halls.length,
            itemBuilder: (context, index) {
              final hall = _halls[index];
              final hallId = hall['hall_id'];
              final hasArrangements = _seatingArrangements.containsKey(hallId);
              final arrangementCount = hasArrangements
                  ? _seatingArrangements[hallId]!
                      .values
                      .expand((arrangements) => arrangements)
                      .length
                  : 0;

              return ListTile(
                enabled: hasArrangements,
                leading: Icon(
                  Icons.domain,
                  color: hasArrangements ? Colors.green : Colors.grey,
                ),
                title: Text(hallId),
                subtitle: Text(
                  hasArrangements
                      ? '$arrangementCount arrangements'
                      : 'No arrangements',
                ),
                onTap: hasArrangements
                    ? () {
                        Navigator.pop(context);
                        _showDeleteHallConfirmation(hallId);
                      }
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSeatingArrangementsByHall(String hallId) async {
    try {
      setState(() => _isLoading = true);

      await Supabase.instance.client
          .from('seating_arr')
          .delete()
          .eq('hall_id', hallId);

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seating arrangements deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      developer.log('Error deleting seating arrangements: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting seating arrangements: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showDeleteHallConfirmation(String hallId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text(
            'Are you sure you want to delete all seating arrangements for hall $hallId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSeatingArrangementsByHall(hallId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _getSessionDisplayName(String session) {
    switch (session.toUpperCase()) {
      case 'FN':
      case 'MORNING':
        return 'Morning';
      case 'AN':
      case 'AFTERNOON':
        return 'Afternoon';
      case 'EN':
      case 'EVENING':
        return 'Evening';
      default:
        return session;
    }
  }

  String _normalizeSession(String session) {
    switch (session.toUpperCase()) {
      case 'FN':
      case 'MORNING':
        return 'MORNING';
      case 'AN':
      case 'AFTERNOON':
        return 'AFTERNOON';
      case 'EN':
      case 'EVENING':
        return 'EVENING';
      default:
        return session.toUpperCase();
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
      // If no record exists, create one
      await Supabase.instance.client.from('seating_visibility').upsert({
        'id': 1,
        'is_visible': false,
      });
    }
  }

  Future<void> _toggleSeatingVisibility() async {
    try {
      setState(() => _isLoading = true);

      // Toggle the value
      final newValue = !_isSeatingVisible;

      // Update in Supabase
      await Supabase.instance.client.from('seating_visibility').upsert({
        'id': 1,
        'is_visible': newValue,
      });

      setState(() {
        _isSeatingVisible = newValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue
              ? 'Seating arrangements are now visible to students'
              : 'Seating arrangements are now hidden from students'),
          backgroundColor: newValue ? Colors.green : Colors.orange,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating seating visibility: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _EditSeatingDialog extends StatefulWidget {
  final Map<String, dynamic> arrangement;
  final List<Map<String, dynamic>> availableHalls;

  const _EditSeatingDialog({
    required this.arrangement,
    required this.availableHalls,
    Key? key,
  }) : super(key: key);

  @override
  State<_EditSeatingDialog> createState() => _EditSeatingDialogState();
}

class _EditSeatingDialogState extends State<_EditSeatingDialog> {
  late String selectedHall;
  late int selectedColumn;
  late int selectedRow;
  late int maxColumns;
  late int maxRows;

  @override
  void initState() {
    super.initState();
    selectedHall = widget.arrangement['hall_id'];
    selectedColumn = widget.arrangement['column_no'];
    selectedRow = widget.arrangement['row_no'];
    _updateMaxDimensions();
  }

  void _updateMaxDimensions() {
    final hall = widget.availableHalls.firstWhere(
      (h) => h['hall_id'] == selectedHall,
      orElse: () => widget.availableHalls.first,
    );
    maxColumns = hall['no_of_columns'];
    maxRows = hall['no_of_rows'];

    // Ensure selected values are within bounds
    if (selectedColumn >= maxColumns) {
      selectedColumn = maxColumns - 1;
    }
    if (selectedRow >= maxRows) {
      selectedRow = maxRows - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Seating Arrangement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: selectedHall,
            decoration: const InputDecoration(labelText: 'Hall'),
            items: widget.availableHalls.map<DropdownMenuItem<String>>((hall) {
              return DropdownMenuItem<String>(
                value: hall['hall_id'],
                child: Text(hall['hall_id']),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedHall = value;
                  _updateMaxDimensions();
                });
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: selectedColumn,
                  decoration: const InputDecoration(labelText: 'Column'),
                  items: List.generate(maxColumns, (index) {
                    return DropdownMenuItem<int>(
                      value: index,
                      child: Text((index + 1).toString()),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedColumn = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: selectedRow,
                  decoration: const InputDecoration(labelText: 'Row'),
                  items: List.generate(maxRows, (index) {
                    return DropdownMenuItem<int>(
                      value: index,
                      child: Text((index + 1).toString()),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedRow = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {
            'hall_id': selectedHall,
            'column_no': selectedColumn,
            'row_no': selectedRow,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DateFilterDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const _DateFilterDialog({
    this.initialStartDate,
    this.initialEndDate,
    Key? key,
  }) : super(key: key);

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  DateTime? startDate;
  DateTime? endDate;
  final DateTime _minDate = DateTime(2020);
  final DateTime _maxDate = DateTime(2026);

  @override
  void initState() {
    super.initState();
    startDate = widget.initialStartDate;
    endDate = widget.initialEndDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Dates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Start Date'),
            subtitle: Text(
              startDate != null
                  ? DateFormat('MMMM d, y').format(startDate!)
                  : 'Not set',
            ),
            trailing: startDate != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        startDate = null;
                        // Reset end date if it's before the new start date
                        if (endDate != null &&
                            (startDate == null ||
                                endDate!.isBefore(startDate!))) {
                          endDate = null;
                        }
                      });
                    },
                  )
                : null,
            onTap: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: startDate ?? now,
                firstDate: _minDate,
                lastDate: endDate ?? _maxDate,
              );
              if (date != null) {
                setState(() {
                  startDate = date;
                  // Reset end date if it's before the new start date
                  if (endDate != null && endDate!.isBefore(startDate!)) {
                    endDate = null;
                  }
                });
              }
            },
          ),
          ListTile(
            title: const Text('End Date'),
            subtitle: Text(
              endDate != null
                  ? DateFormat('MMMM d, y').format(endDate!)
                  : 'Not set',
            ),
            trailing: endDate != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => endDate = null);
                    },
                  )
                : null,
            onTap: () async {
              if (startDate == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a start date first'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              final date = await showDatePicker(
                context: context,
                initialDate: endDate ?? startDate!,
                firstDate: startDate!,
                lastDate: _maxDate,
              );
              if (date != null) {
                setState(() => endDate = date);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, {
              'start': startDate,
              'end': endDate,
            });
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
