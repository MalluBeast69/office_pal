import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math' as math;
import 'seating_arrangement/select_exam_page.dart';
import 'dart:developer' as developer;

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
  DateTime _focusedDay = DateTime.now();
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

  @override
  void initState() {
    super.initState();
    _loadData();
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
            exam!inner(*),
            hall:hall_id(*)
          ''').order('created_at');

      final arrangements = List<Map<String, dynamic>>.from(response);
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
      final session = exam['session'];

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
      _filteredArrangements = Map.from(_filteredArrangements)
        ..forEach((date, sessions) {
          sessions.removeWhere((session, _) => session != _selectedSession);
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
                _buildDetailRow('Session',
                    exam['session'] == 'FN' ? 'Morning' : 'Afternoon'),
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
            'Hall ${_selectedHall}',
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
    final sessions = <String, List<Map<String, dynamic>>>{};
    for (final arrangement in arrangements) {
      final session = arrangement['exam']['session'];
      sessions[session] ??= [];
      sessions[session]!.add(arrangement);
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.access_time),
                const SizedBox(width: 8),
                Text(
                  'Select Session',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions.keys.elementAt(index);
                final sessionArrangements = sessions[session]!;
                final examCount = sessionArrangements.length;
                final ismorning = session == 'FN';

                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: ismorning ? Colors.blue : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        ismorning ? Icons.wb_sunny : Icons.wb_twilight,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                        ismorning ? 'Morning Session' : 'Afternoon Session'),
                    subtitle: Text('$examCount students assigned'),
                    onTap: () {
                      setState(() {
                        _selectedSession = session;
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

  Widget _buildVisualLayout(
      Map<String, List<Map<String, dynamic>>> arrangements) {
    final selectedHallData = _halls.firstWhere(
      (hall) => hall['hall_id'] == _selectedHall,
      orElse: () => {'no_of_columns': 0, 'no_of_rows': 0},
    );

    final dateStr = _selectedDate!.toString().split(' ')[0];
    final dateArrangements = arrangements[dateStr]!;
    final sessionArrangements = dateArrangements
        .where((arr) => arr['exam']['session'] == _selectedSession)
        .toList();

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
                    _selectedSession == 'FN' ? Colors.blue : Colors.orange,
                radius: 16,
                child: Text(
                  _selectedSession!,
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
          child: Column(
            children: [
              if (_isSeatingGridExpanded) ...[
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildSeatingGrid(
                        selectedHallData['no_of_columns'],
                        selectedHallData['no_of_rows'],
                        {dateStr: sessionArrangements},
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child:
                      _buildArrangementDetails({dateStr: sessionArrangements}),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.grid_view,
                        size: 20,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Seating grid is collapsed',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      _buildArrangementDetails({dateStr: sessionArrangements}),
                ),
              ],
            ],
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

    // Calculate sequential seat number
    final seatNumber =
        (row * arrangements.first['hall']['no_of_columns'] + col + 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isOccupied ? () => _viewSeatingArrangement(arrangement) : null,
        borderRadius: BorderRadius.circular(8),
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
                    ? (exam?['session'] == 'FN' ? Colors.blue : Colors.orange)
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
                              '${exam['time']} | ${studentCount} students',
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTopBar(),
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
                exam['session'] == 'FN' ? 'Morning' : 'Afternoon',
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
