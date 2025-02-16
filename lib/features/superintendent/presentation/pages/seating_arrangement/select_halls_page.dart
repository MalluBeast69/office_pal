import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import 'select_faculty_page.dart';
import 'dart:developer' as developer;

class SelectHallsPage extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> exams;
  final List<String> selectedStudents;

  const SelectHallsPage({
    super.key,
    required this.exams,
    required this.selectedStudents,
  });

  @override
  ConsumerState<SelectHallsPage> createState() => _SelectHallsPageState();
}

class _SelectHallsPageState extends ConsumerState<SelectHallsPage> {
  List<Map<String, dynamic>> _halls = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, Set<String>> _selectedHallsBySession = {};
  Map<String, Map<String, int>> _capacityNeededPerDateAndSession = {};
  final int _maxCapacityNeeded = 0;
  String? _selectedDepartment;
  List<String> _departments = [];
  String? _selectedSession;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      final registeredStudentsResponse =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            course_code,
            is_reguler,
            student!inner (
              student_name,
              dept_id,
              semester
            )
          ''').in_('student_reg_no', widget.selectedStudents);

      _students = List<Map<String, dynamic>>.from(registeredStudentsResponse);

      final studentsByDateAndSession =
          <String, Map<String, Map<String, Set<String>>>>{};

      for (final exam in widget.exams) {
        final date = exam['exam_date'].toString().split(' ')[0];
        final session = exam['session'] as String;
        final courseId = exam['course_id'] as String;

        studentsByDateAndSession[date] ??= {};
        studentsByDateAndSession[date]![session] ??= {
          'regular': <String>{},
          'supplementary': <String>{},
          'all': <String>{},
        };

        final examStudents =
            _students.where((s) => s['course_code'] == courseId);

        var regularCount = 0;
        var supplementaryCount = 0;

        for (final student in examStudents) {
          final studentId = student['student_reg_no'] as String;
          final isRegular = student['is_reguler'] as bool;

          if (!studentsByDateAndSession[date]![session]!['all']!
              .contains(studentId)) {
            studentsByDateAndSession[date]![session]!['all']!.add(studentId);

            if (isRegular) {
              studentsByDateAndSession[date]![session]!['regular']!
                  .add(studentId);
              regularCount++;
            } else {
              studentsByDateAndSession[date]![session]!['supplementary']!
                  .add(studentId);
              supplementaryCount++;
            }
          }
        }
      }

      _capacityNeededPerDateAndSession = {};
      for (var dateEntry in studentsByDateAndSession.entries) {
        final date = dateEntry.key;
        _capacityNeededPerDateAndSession[date] = {};

        for (var sessionEntry in dateEntry.value.entries) {
          final session = sessionEntry.key;
          final allStudents = sessionEntry.value['all']!;
          _capacityNeededPerDateAndSession[date]![session] = allStudents.length;
        }
      }

      final hallsResponse = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true);

      setState(() {
        _halls = List<Map<String, dynamic>>.from(hallsResponse);
        _departments = _halls
            .map((h) => h['hall_dept'] as String)
            .toSet()
            .toList()
          ..sort();
        _isLoading = false;

        // Initialize selected halls for each session
        _selectedHallsBySession = {};
        for (final dateEntry in _capacityNeededPerDateAndSession.entries) {
          for (final sessionEntry in dateEntry.value.entries) {
            final session = sessionEntry.key;
            // Auto-select all halls for each session
            _selectedHallsBySession[session] =
                _halls.map((h) => h['hall_id'].toString()).toSet();
          }
        }

        if (_capacityNeededPerDateAndSession.isNotEmpty) {
          final firstDate = _capacityNeededPerDateAndSession.keys.first;
          if (_capacityNeededPerDateAndSession[firstDate]?.isNotEmpty ??
              false) {
            _selectedSession =
                _capacityNeededPerDateAndSession[firstDate]!.keys.first;
          }
        }

        // Show warning snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'We are still working on finding the best halls. For now, we are selecting all available halls.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      });
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

  List<Map<String, dynamic>> _filterAndSortHalls() {
    final filtered = _halls.where((hall) {
      // Search filter
      final hallId = hall['hall_id']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      if (!hallId.contains(searchLower)) {
        return false;
      }

      // Department filter
      if (_selectedDepartment != null &&
          hall['hall_dept'] != _selectedDepartment) {
        return false;
      }

      return true;
    }).toList();

    // Sort halls by department and capacity
    filtered.sort((a, b) {
      // First sort by department to keep halls from same department together
      final deptCompare =
          (a['hall_dept'] as String).compareTo(b['hall_dept'] as String);
      if (deptCompare != 0) return deptCompare;

      // Then sort by capacity (larger halls first)
      return (b['capacity'] as int).compareTo(a['capacity'] as int);
    });

    return filtered;
  }

  int _getSelectedCapacityForSession(String session) {
    final halls = _selectedHallsBySession[session] ?? <String>{};
    return halls.fold(0, (sum, hallId) {
      final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
      return sum + (hall['capacity'] as int);
    });
  }

  int _getCapacityNeededForSession(String session) {
    // Find the maximum capacity needed for this session across all dates
    int maxCapacity = 0;

    for (final dateEntry in _capacityNeededPerDateAndSession.entries) {
      final sessionCapacity = dateEntry.value[session] ?? 0;
      if (sessionCapacity > maxCapacity) {
        maxCapacity = sessionCapacity;
      }
    }

    return maxCapacity;
  }

  String _getSessionDisplayName(String session) {
    switch (session) {
      case 'MORNING':
        return 'Morning';
      case 'AFTERNOON':
        return 'Afternoon';
      case 'EVENING':
        return 'Evening';
      default:
        return session;
    }
  }

  void _selectHall(String hallId, bool selected) {
    final currentSession = _selectedSession;
    if (currentSession == null) return;

    setState(() {
      // Initialize the set if it doesn't exist
      _selectedHallsBySession[currentSession] ??= <String>{};

      if (selected) {
        _selectedHallsBySession[currentSession]!.add(hallId);
      } else {
        _selectedHallsBySession[currentSession]!.remove(hallId);
      }
    });
  }

  int calculateEffectiveHallCapacity(Map<String, dynamic> hall) {
    final rows = hall['no_of_rows'] as int;
    final cols = hall['no_of_columns'] as int;

    // Create a grid and try to fill it with dummy courses
    final grid = List.generate(
      rows,
      (_) => List<String?>.filled(cols, null, growable: false),
      growable: false,
    );

    int effectiveCapacity = 0;
    final dummyCourses = ['TEST1', 'TEST2', 'TEST3', 'TEST4'];
    var currentCourseIndex = 0;

    // Try to fill positions in a more efficient pattern using multiple dummy courses
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (grid[row][col] == null) {
          // Try each dummy course until we find one that fits
          for (var i = 0; i < dummyCourses.length; i++) {
            final courseIndex = (currentCourseIndex + i) % dummyCourses.length;
            if (_isSeatSuitable(grid, row, col, dummyCourses[courseIndex])) {
              grid[row][col] = dummyCourses[courseIndex];
              effectiveCapacity++;
              currentCourseIndex = (courseIndex + 1) % dummyCourses.length;
              break;
            }
          }
        }
      }
    }

    // Return a slightly reduced capacity to account for real-world distribution
    return (effectiveCapacity * 0.95).floor();
  }

  bool _isSeatSuitable(
      List<List<String?>> grid, int row, int col, String courseId) {
    final rows = grid.length;
    final cols = grid[0].length;

    // Check immediate adjacent and diagonal positions
    final positions = [
      [-1, -1], // Top-left
      [-1, 0], // Top
      [-1, 1], // Top-right
      [0, -1], // Left
      [0, 1], // Right
      [1, -1], // Bottom-left
      [1, 0], // Bottom
      [1, 1], // Bottom-right
    ];

    // Check each position
    for (final pos in positions) {
      final newRow = row + pos[0];
      final newCol = col + pos[1];

      if (newRow >= 0 && newRow < rows && newCol >= 0 && newCol < cols) {
        final adjacentCourse = grid[newRow][newCol];
        if (adjacentCourse == courseId) {
          return false; // Don't allow same course in adjacent or diagonal positions
        }
      }
    }

    return true;
  }

  // Generate positions in a spiral pattern from center
  List<List<int>> _generateSpiralPositions(
      int rows, int cols, int startRow, int startCol) {
    final positions = <List<int>>[];
    final maxDistance = math.max(
      math.max(startRow, rows - 1 - startRow),
      math.max(startCol, cols - 1 - startCol),
    );

    for (var distance = 0; distance <= maxDistance; distance++) {
      // Add positions in a square pattern around the center
      for (var i = -distance; i <= distance; i++) {
        for (var j = -distance; j <= distance; j++) {
          // Only add positions that form the current square's perimeter
          if (i.abs() == distance || j.abs() == distance) {
            final row = startRow + i;
            final col = startCol + j;
            if (row >= 0 && row < rows && col >= 0 && col < cols) {
              positions.add([row, col]);
            }
          }
        }
      }
    }

    return positions;
  }

  Map<String, dynamic> simulateSeatingArrangement(
    List<Map<String, dynamic>> halls,
    List<Map<String, dynamic>> students,
    List<Map<String, dynamic>> exams,
  ) {
    final seatingGrid = <String, List<Map<String, dynamic>>>{};
    var totalSeated = 0;
    final assignedStudents = <String>{};

    // Initialize grids for each hall
    for (final hall in halls) {
      final hallId = hall['hall_id'].toString();
      seatingGrid[hallId] = [];
    }

    // Group students by exam
    final studentsByExam = <String, List<Map<String, dynamic>>>{};
    for (final exam in exams) {
      final courseId = exam['course_id'] as String;
      studentsByExam[courseId] = students
          .where((s) =>
              s['course_code'] == courseId &&
              !assignedStudents.contains(s['student_reg_no']))
          .toList();
    }

    // Sort exams by number of students (largest first)
    final sortedExams = exams.toList()
      ..sort((a, b) {
        final aCount = studentsByExam[a['course_id']]?.length ?? 0;
        final bCount = studentsByExam[b['course_id']]?.length ?? 0;
        return bCount.compareTo(aCount);
      });

    // Process each exam
    for (final exam in sortedExams) {
      final courseId = exam['course_id'] as String;
      final examStudents = studentsByExam[courseId] ?? [];

      if (examStudents.isEmpty) continue;

      // Try to assign students to halls
      for (final hall in halls) {
        final hallId = hall['hall_id'].toString();
        final rows = hall['no_of_rows'] as int;
        final cols = hall['no_of_columns'] as int;

        // Create a grid to track occupied seats
        final grid = List.generate(
          rows,
          (_) => List<String?>.filled(cols, null, growable: false),
          growable: false,
        );

        // Fill in existing assignments
        for (final assignment in seatingGrid[hallId]!) {
          grid[assignment['row_no']][assignment['column_no']] =
              assignment['course_code'];
        }

        // Try to seat remaining students
        for (final student in examStudents.where(
          (s) => !assignedStudents.contains(s['student_reg_no']),
        )) {
          var seated = false;

          // Try to find a suitable seat using spiral pattern
          final centerRow = rows ~/ 2;
          final centerCol = cols ~/ 2;
          final positions =
              _generateSpiralPositions(rows, cols, centerRow, centerCol);

          for (final pos in positions) {
            final row = pos[0];
            final col = pos[1];

            if (grid[row][col] == null &&
                _isSeatSuitable(grid, row, col, courseId)) {
              seatingGrid[hallId]!.add({
                'student_reg_no': student['student_reg_no'],
                'column_no': col,
                'row_no': row,
                'course_code': courseId,
                'student': student['student'],
                'is_supplementary': student['is_reguler'] != true,
              });
              grid[row][col] = courseId;
              assignedStudents.add(student['student_reg_no']);
              totalSeated++;
              seated = true;
              break;
            }
          }

          if (!seated) break; // If we can't seat a student, move to next hall
        }
      }
    }

    final totalEffectiveCapacity = halls.fold<int>(
      0,
      (sum, hall) => sum + calculateEffectiveHallCapacity(hall),
    );

    final success = totalSeated == students.length;
    final efficiency = totalSeated / totalEffectiveCapacity;

    return {
      'success': success,
      'seated_count': totalSeated,
      'total_students': students.length,
      'seating_grid': seatingGrid,
      'efficiency': efficiency,
    };
  }

  void _autoSelectHalls() {
    // Get all unique sessions
    final allSessions = _capacityNeededPerDateAndSession.values
        .expand((sessions) => sessions.keys)
        .toSet()
        .toList();

    // Create a temporary map to store new selections
    final newSelections = <String, Set<String>>{};

    // Process each session
    for (final session in allSessions) {
      final availableHalls = List<Map<String, dynamic>>.from(_halls);

      // Calculate total students for this session
      final totalStudents = _getCapacityNeededForSession(session);

      // Initialize selection set for this session
      newSelections[session] = {};

      // Get all exams for this session
      final examsInSession = widget.exams
          .where((exam) =>
              exam['session'] == session &&
              exam['exam_date'].toString().split(' ')[0] ==
                  _capacityNeededPerDateAndSession.keys.first)
          .toList();

      // Get all students for this session
      final studentsInSession = <Map<String, dynamic>>[];
      for (final studentRegNo in widget.selectedStudents) {
        final registeredStudent = _students.firstWhere(
          (s) => s['student_reg_no'] == studentRegNo,
          orElse: () => <String, dynamic>{},
        );

        if (registeredStudent.isNotEmpty) {
          final courseId = registeredStudent['course_code'] as String;
          if (examsInSession.any((exam) => exam['course_id'] == courseId)) {
            studentsInSession.add(registeredStudent);
          }
        }
      }

      // Sort halls by capacity (largest first)
      availableHalls.sort((a, b) => calculateEffectiveHallCapacity(b)
          .compareTo(calculateEffectiveHallCapacity(a)));

      var remainingStudents = totalStudents;
      var selectedHalls = <Map<String, dynamic>>[];

      // Select halls until we have enough capacity
      for (final hall in availableHalls) {
        if (remainingStudents <= 0) break;

        final effectiveCapacity = calculateEffectiveHallCapacity(hall);
        if (effectiveCapacity > 0) {
          selectedHalls.add(hall);
          remainingStudents -= effectiveCapacity;
          newSelections[session]!.add(hall['hall_id'].toString());
        }
      }
    }

    // Update the state with new selections
    setState(() {
      _selectedHallsBySession = Map<String, Set<String>>.from(newSelections);
      // If no session is currently selected, select the first one
      if (_selectedSession == null && allSessions.isNotEmpty) {
        _selectedSession = allSessions.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredHalls = _filterAndSortHalls();
    final currentSessionCapacity = _selectedSession != null
        ? _getSelectedCapacityForSession(_selectedSession!)
        : 0;
    final currentSessionNeeded = _selectedSession != null
        ? _getCapacityNeededForSession(_selectedSession!)
        : 0;

    // Show dialog on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Text('Hall Selection'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Please use auto-select while we fix manual hall selection.'),
              SizedBox(height: 8),
              Text(
                'Manual selection is temporarily disabled.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Halls'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text(
                'Auto Select',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: _selectedSession != null ? _autoSelectHalls : null,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(280),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Session selection chips
                Wrap(
                  spacing: 8,
                  children: _capacityNeededPerDateAndSession.values
                      .expand((sessions) => sessions.keys)
                      .toSet()
                      .map((session) {
                    final isSelected = _selectedSession == session;
                    return FilterChip(
                      selected: isSelected,
                      label: Text(_getSessionDisplayName(session)),
                      onSelected: (selected) {
                        setState(
                            () => _selectedSession = selected ? session : null);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by hall ID',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedDepartment,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Departments'),
                    ),
                    ..._departments.map((dept) => DropdownMenuItem(
                          value: dept,
                          child: Text(dept),
                        )),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedDepartment = value),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: currentSessionCapacity >= currentSessionNeeded
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentSessionCapacity >= currentSessionNeeded
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (_selectedSession != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              currentSessionCapacity >= currentSessionNeeded
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color:
                                  currentSessionCapacity >= currentSessionNeeded
                                      ? Colors.green
                                      : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Capacity Needed: $currentSessionNeeded',
                              style: TextStyle(
                                color: currentSessionCapacity >=
                                        currentSessionNeeded
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selected Capacity: $currentSessionCapacity',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      ..._capacityNeededPerDateAndSession.entries.map(
                        (dateEntry) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateEntry.key,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Wrap(
                              spacing: 8,
                              children:
                                  dateEntry.value.entries.map((sessionEntry) {
                                final isCurrentSession =
                                    sessionEntry.key == _selectedSession;
                                return Chip(
                                  label: Text(
                                    '${_getSessionDisplayName(sessionEntry.key)}: ${sessionEntry.value}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrentSession
                                          ? FontWeight.bold
                                          : null,
                                    ),
                                  ),
                                  backgroundColor: isCurrentSession
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  labelStyle: TextStyle(
                                    color: isCurrentSession
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_selectedSession == null)
                const Expanded(
                  child: Center(
                    child: Text('Please select a session to continue'),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 1200
                            ? 4
                            : MediaQuery.of(context).size.width > 800
                                ? 3
                                : 2,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filteredHalls.length,
                      itemBuilder: (context, index) {
                        final hall = filteredHalls[index];
                        final hallId = hall['hall_id'];
                        final isSelected =
                            _selectedHallsBySession[_selectedSession]
                                    ?.contains(hallId) ??
                                false;

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(0.5),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _selectHall(hallId, !isSelected),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              hallId,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              hall['hall_dept'],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (value) =>
                                            _selectHall(hallId, value ?? false),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Capacity: ${hall['capacity']}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${hall['no_of_columns']} × ${hall['no_of_rows']} seats',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
          // Grey overlay
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FilledButton.icon(
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Next'),
          onPressed: _selectedHallsBySession.values.every(
            (halls) {
              final session = _selectedHallsBySession.entries
                  .firstWhere((e) => e.value == halls)
                  .key;
              return _getSelectedCapacityForSession(session) >=
                  _getCapacityNeededForSession(session);
            },
          )
              ? () {
                  // Create a list of hall-session pairs with correct session information
                  final allSelectedHallsWithSessions = <Map<String, dynamic>>[];

                  // Iterate through each session and its halls
                  for (final sessionEntry in _selectedHallsBySession.entries) {
                    final session = sessionEntry.key;
                    final hallIds = sessionEntry.value;

                    // For each hall in this session
                    for (final hallId in hallIds) {
                      // Find the hall details
                      final hall = _halls.firstWhere(
                        (h) => h['hall_id'].toString() == hallId,
                        orElse: () => <String, dynamic>{},
                      );

                      if (hall.isNotEmpty) {
                        allSelectedHallsWithSessions.add({
                          ...hall,
                          'session': session,
                          'exam_date': _capacityNeededPerDateAndSession
                              .entries.first.key,
                        });
                      }
                    }
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SelectFacultyPage(
                        exams: widget.exams,
                        selectedStudents: widget.selectedStudents,
                        selectedHalls: allSelectedHallsWithSessions,
                      ),
                    ),
                  );
                }
              : null,
        ),
      ),
    );
  }
}
