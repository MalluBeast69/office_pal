import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' show max;
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
  int _maxCapacityNeeded = 0;
  String? _selectedDepartment;
  List<String> _departments = [];
  String? _selectedSession;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // Load registered students data first
      final registeredStudentsResponse =
          await Supabase.instance.client.from('registered_students').select('''
            student_reg_no,
            course_code,
            is_reguler
          ''').in_('student_reg_no', widget.selectedStudents);

      final registeredStudents =
          List<Map<String, dynamic>>.from(registeredStudentsResponse);
      developer.log('Loaded ${registeredStudents.length} registered students');

      // Group students by date and session, tracking unique students
      final studentsByDateAndSession =
          <String, Map<String, Map<String, Set<String>>>>{};

      for (final exam in widget.exams) {
        final date = exam['exam_date'].toString().split(' ')[0];
        final session = exam['session'] as String;
        final courseId = exam['course_id'] as String;

        developer.log('Processing exam: $courseId on $date, session: $session');

        studentsByDateAndSession[date] ??= {};
        studentsByDateAndSession[date]![session] ??= {
          'regular': <String>{},
          'supplementary': <String>{},
          'all': <String>{}, // Track all students regardless of type
        };

        // Find students registered for this course
        final examStudents =
            registeredStudents.where((s) => s['course_code'] == courseId);

        var regularCount = 0;
        var supplementaryCount = 0;

        // Add students to sets to ensure uniqueness
        for (final student in examStudents) {
          final studentId = student['student_reg_no'] as String;
          final isRegular = student['is_reguler'] as bool;

          // Only count if student hasn't been added to either category
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

        developer.log(
            'Students for exam $courseId: Regular: $regularCount, Supplementary: $supplementaryCount');
      }

      // Calculate capacity needed for each date and session
      _capacityNeededPerDateAndSession = {};
      for (var dateEntry in studentsByDateAndSession.entries) {
        final date = dateEntry.key;
        _capacityNeededPerDateAndSession[date] = {};

        for (var sessionEntry in dateEntry.value.entries) {
          final session = sessionEntry.key;
          final regularStudents = sessionEntry.value['regular']!;
          final supplementaryStudents = sessionEntry.value['supplementary']!;
          final allStudents = sessionEntry.value['all']!;

          final totalRegular = regularStudents.length;
          final totalSupplementary = supplementaryStudents.length;
          final totalStudents = allStudents.length;

          // Store actual student count
          _capacityNeededPerDateAndSession[date]![session] = totalStudents;

          developer.log('Session $session total students: $totalStudents ' +
              '(Regular: $totalRegular, Supplementary: $totalSupplementary)');
          developer
              .log('Regular students: ${regularStudents.toList().join(", ")}');
          developer.log(
              'Supplementary students: ${supplementaryStudents.toList().join(", ")}');
          developer
              .log('All unique students: ${allStudents.toList().join(", ")}');
        }
      }

      // Load halls data
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
            _selectedHallsBySession[sessionEntry.key] = {};
          }
        }

        // Set initial selected session
        if (_capacityNeededPerDateAndSession.isNotEmpty) {
          final firstDate = _capacityNeededPerDateAndSession.keys.first;
          if (_capacityNeededPerDateAndSession[firstDate]?.isNotEmpty ??
              false) {
            _selectedSession =
                _capacityNeededPerDateAndSession[firstDate]!.keys.first;
            developer.log('Initial selected session: $_selectedSession');
          }
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
    developer.log('Calculating capacity needed for session: $session');

    for (final dateEntry in _capacityNeededPerDateAndSession.entries) {
      final sessionCapacity = dateEntry.value[session] ?? 0;
      if (sessionCapacity > maxCapacity) {
        maxCapacity = sessionCapacity;
      }
    }

    developer.log('Total students for $session session: $maxCapacity');
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
    if (_selectedSession == null) return;

    final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
    setState(() {
      if (selected) {
        _selectedHallsBySession[_selectedSession]?.add(hallId);
      } else {
        _selectedHallsBySession[_selectedSession]?.remove(hallId);
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
  List<List<int>> _generateSpiralPositions(int rows, int cols) {
    final positions = <List<int>>[];
    final centerRow = rows ~/ 2;
    final centerCol = cols ~/ 2;

    // Try different starting points to maximize spacing
    final startPoints = [
      [centerRow, centerCol], // Center
      [0, 0], // Top-left
      [0, cols - 1], // Top-right
      [rows - 1, 0], // Bottom-left
      [rows - 1, cols - 1], // Bottom-right
    ];

    for (final start in startPoints) {
      final pattern = _generatePatternFromStart(start[0], start[1], rows, cols);
      positions.addAll(pattern);
    }

    // Remove duplicates while preserving order
    final seen = <String>{};
    return positions.where((pos) {
      final key = '${pos[0]},${pos[1]}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  List<List<int>> _generatePatternFromStart(
      int startRow, int startCol, int rows, int cols) {
    final positions = <List<int>>[];
    final visited = List.generate(rows, (_) => List.filled(cols, false));

    // Directions: right, down, left, up
    final directions = [
      [0, 1],
      [1, 0],
      [0, -1],
      [-1, 0],
    ];

    var currentRow = startRow;
    var currentCol = startCol;
    var dirIndex = 0;

    while (positions.length < rows * cols) {
      if (_isValidPosition(currentRow, currentCol, rows, cols) &&
          !visited[currentRow][currentCol]) {
        positions.add([currentRow, currentCol]);
        visited[currentRow][currentCol] = true;
      }

      // Try to move in current direction
      var nextRow = currentRow + directions[dirIndex][0];
      var nextCol = currentCol + directions[dirIndex][1];

      // Change direction if we can't move further
      if (!_isValidPosition(nextRow, nextCol, rows, cols) ||
          visited[nextRow][nextCol]) {
        dirIndex = (dirIndex + 1) % 4;
        nextRow = currentRow + directions[dirIndex][0];
        nextCol = currentCol + directions[dirIndex][1];

        // If we can't move in any direction, break
        if (!_isValidPosition(nextRow, nextCol, rows, cols) ||
            visited[nextRow][nextCol]) {
          break;
        }
      }

      currentRow = nextRow;
      currentCol = nextCol;
    }

    return positions;
  }

  bool _isValidPosition(int row, int col, int rows, int cols) {
    return row >= 0 && row < rows && col >= 0 && col < cols;
  }

  // Try to seat students from each exam with multiple patterns
  bool _trySeatingInHall(
    Map<String, List<List<List<String?>>>> seatingGrid,
    String hallId,
    String courseId,
    int targetCount,
    int rows,
    int cols,
    int seatedForExam,
    int totalSeated,
    int totalStudents,
  ) {
    final patterns = [
      _generateSpiralPositions(rows, cols),
      _generatePatternFromStart(0, 0, rows, cols),
      _generatePatternFromStart(rows - 1, cols - 1, rows, cols),
    ];

    for (final positions in patterns) {
      var success = true;
      final tempGrid = List.generate(
        rows,
        (r) => List.generate(
          cols,
          (c) => List<String?>.from(seatingGrid[hallId]![r][c]),
          growable: false,
        ),
        growable: false,
      );

      var tempSeated = seatedForExam;
      var tempTotal = totalSeated;

      for (final pos in positions) {
        if (tempSeated >= targetCount || tempTotal >= totalStudents) break;

        final row = pos[0];
        final col = pos[1];

        if (tempGrid[row][col][0] == null &&
            _isSeatSuitable(
                tempGrid.map((r) => r.map((c) => c[0]).toList()).toList(),
                row,
                col,
                courseId)) {
          tempGrid[row][col][0] = courseId;
          tempSeated++;
          tempTotal++;
        }
      }

      if (tempSeated == targetCount || tempTotal == totalStudents) {
        // Copy successful arrangement back to main grid
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            seatingGrid[hallId]![r][c][0] = tempGrid[r][c][0];
          }
        }
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic> simulateSeatingArrangement(
      List<Map<String, dynamic>> halls,
      int totalStudents,
      List<Map<String, dynamic>> exams) {
    final seatingGrid = <String, List<List<List<String?>>>>{};
    var totalSeated = 0;

    // Initialize grids for each hall
    for (final hall in halls) {
      final rows = hall['no_of_rows'] as int;
      final cols = hall['no_of_columns'] as int;
      final hallId = hall['hall_id'].toString();

      seatingGrid[hallId] = List.generate(
        rows,
        (_) => List.generate(
          cols,
          (_) => List<String?>.filled(1, null, growable: false),
          growable: false,
        ),
        growable: false,
      );
    }

    // Calculate student count per exam
    final examStudentCounts = <String, int>{};
    var totalExamStudents = 0;

    // First pass: collect all students for each course
    for (final exam in exams) {
      final courseId = exam['course_id'] as String;
      final registeredStudents = widget.selectedStudents.where((studentId) {
        return widget.exams.any((e) =>
            e['course_id'] == courseId && e['session'] == exam['session']);
      }).length;

      examStudentCounts[courseId] = registeredStudents;
      totalExamStudents += registeredStudents;
    }

    // Sort exams by size (largest first) to optimize seating
    final sortedExams = List<Map<String, dynamic>>.from(exams)
      ..sort((a, b) {
        final aCount = examStudentCounts[a['course_id']] ?? 0;
        final bCount = examStudentCounts[b['course_id']] ?? 0;
        return bCount.compareTo(aCount);
      });

    // Try to seat students from each exam
    for (final exam in sortedExams) {
      final courseId = exam['course_id'] as String;
      final targetCount = examStudentCounts[courseId] ?? 0;
      var seatedForExam = 0;

      // Calculate maximum students that can be seated in each hall for this course
      final hallCapacities = <String, int>{};
      for (final hall in halls) {
        final hallId = hall['hall_id'].toString();
        final rows = hall['no_of_rows'] as int;
        final cols = hall['no_of_columns'] as int;
        var availableSeats = 0;

        // Count available seats considering spacing requirements
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            if (seatingGrid[hallId]![r][c][0] == null &&
                _isSeatSuitable(
                    seatingGrid[hallId]!
                        .map((r) => r.map((c) => c[0]).toList())
                        .toList(),
                    r,
                    c,
                    courseId)) {
              availableSeats++;
            }
          }
        }
        hallCapacities[hallId] = availableSeats;
      }

      // Sort halls by available capacity (largest first)
      final sortedHalls = List<Map<String, dynamic>>.from(halls)
        ..sort((a, b) {
          final aCapacity = hallCapacities[a['hall_id'].toString()] ?? 0;
          final bCapacity = hallCapacities[b['hall_id'].toString()] ?? 0;
          return bCapacity.compareTo(aCapacity);
        });

      // Try to seat students in each hall
      for (final hall in sortedHalls) {
        if (seatedForExam >= targetCount || totalSeated >= totalStudents) break;

        final hallId = hall['hall_id'].toString();
        final rows = hall['no_of_rows'] as int;
        final cols = hall['no_of_columns'] as int;

        // Calculate remaining students for this exam
        final remainingForExam = targetCount - seatedForExam;
        final availableInHall = hallCapacities[hallId] ?? 0;

        // Try to seat as many students as possible in this hall
        final studentsToTry = remainingForExam < availableInHall
            ? remainingForExam
            : availableInHall;

        if (studentsToTry > 0) {
          final success = _trySeatingInHall(
            seatingGrid,
            hallId,
            courseId,
            studentsToTry,
            rows,
            cols,
            seatedForExam,
            totalSeated,
            totalStudents,
          );

          if (success) {
            // Count how many were actually seated
            var newSeated = 0;
            for (var r = 0; r < rows; r++) {
              for (var c = 0; c < cols; c++) {
                if (seatingGrid[hallId]![r][c][0] == courseId) {
                  newSeated++;
                }
              }
            }
            seatedForExam += newSeated;
            totalSeated += newSeated;

            developer.log(
                'Seated $newSeated students from course $courseId in hall $hallId');
          }
        }
      }

      developer.log(
          'Seated $seatedForExam/$targetCount students for course $courseId');
    }

    final totalEffectiveCapacity = halls.fold<int>(
        0, (sum, hall) => sum + calculateEffectiveHallCapacity(hall));
    final success = totalSeated == totalStudents;
    final efficiency = totalSeated / totalEffectiveCapacity;

    developer.log('Total students seated: $totalSeated/$totalStudents');
    developer.log('Total effective capacity: $totalEffectiveCapacity');
    developer.log(
        'Success: $success, Efficiency: ${(efficiency * 100).toStringAsFixed(1)}%');

    return {
      'success': success,
      'seated_count': totalSeated,
      'total_students': totalStudents,
      'seating_grid': seatingGrid,
      'efficiency': efficiency,
    };
  }

  void _autoSelectHalls() {
    developer.log('Auto-selecting halls for all sessions');

    // Get all unique sessions
    final allSessions = _capacityNeededPerDateAndSession.values
        .expand((sessions) => sessions.keys)
        .toSet()
        .toList();

    // Create a temporary map to store new selections
    final newSelections = <String, Set<String>>{};

    // Process each session
    for (final session in allSessions) {
      developer.log('Auto-selecting halls for session: $session');
      final availableHalls = List<Map<String, dynamic>>.from(_halls);
      developer.log('Available halls: ${availableHalls.length}');

      // Calculate total students for this session
      final totalStudents = _getCapacityNeededForSession(session);
      developer.log('Total students to seat: $totalStudents');

      // Sort halls by capacity (smallest first)
      availableHalls.sort(
          (a, b) => (a['capacity'] as int).compareTo(b['capacity'] as int));

      // Initialize session set
      newSelections[session] = <String>{};

      // Try each hall individually first
      var bestSolution = <Map<String, dynamic>>[];
      var bestResult = <String, dynamic>{
        'success': false,
        'seated_count': 0,
        'efficiency': 0.0,
      };

      developer.log('Trying individual halls first (smallest to largest)...');
      for (final hall in availableHalls) {
        final effectiveCapacity = calculateEffectiveHallCapacity(hall);
        developer.log(
            'Trying hall ${hall['hall_id']} (raw capacity: ${hall['capacity']}, effective: $effectiveCapacity)');

        if (effectiveCapacity >= totalStudents) {
          final simulationResult = simulateSeatingArrangement(
            [hall],
            totalStudents,
            widget.exams.where((e) => e['session'] == session).toList(),
          );

          final efficiency = simulationResult['seated_count'] / effectiveCapacity;
          developer.log(
              'Hall ${hall['hall_id']} result - Seated: ${simulationResult['seated_count']}/$totalStudents (Efficiency: ${(efficiency * 100).toStringAsFixed(1)}%)');

          if (simulationResult['seated_count'] == totalStudents &&
              (!bestResult['success'] ||
                  efficiency > (bestResult['efficiency'] as double))) {
            bestSolution = [hall];
            bestResult = {
              ...simulationResult,
              'efficiency': efficiency,
              'success': true,
            };
            developer.log(
                'Found better single hall solution with efficiency: ${(efficiency * 100).toStringAsFixed(1)}%');
          }
        }
      }

      // If no single hall works well enough, try combinations
      if (!bestResult['success'] ||
          (bestResult['efficiency'] as double) < 0.7) {
        developer.log(
            'No single hall suitable or efficiency too low, trying combinations...');

        // Try all possible combinations of 2 halls
        for (var i = 0; i < availableHalls.length - 1; i++) {
          for (var j = i + 1; j < availableHalls.length; j++) {
            final combination = [availableHalls[i], availableHalls[j]];
            final totalEffectiveCapacity = combination.fold<int>(
                0, (sum, hall) => sum + calculateEffectiveHallCapacity(hall));

            developer.log(
                'Trying combination: ${combination.map((h) => h['hall_id']).join(", ")} (effective capacity: $totalEffectiveCapacity)');

            if (totalEffectiveCapacity >= totalStudents) {
              final simulationResult = simulateSeatingArrangement(
                combination,
                totalStudents,
                widget.exams.where((e) => e['session'] == session).toList(),
              );

              final efficiency =
                  simulationResult['seated_count'] / totalEffectiveCapacity;
              developer.log(
                  'Combination result - Seated: ${simulationResult['seated_count']}/$totalStudents (Efficiency: ${(efficiency * 100).toStringAsFixed(1)}%)');

              if (simulationResult['seated_count'] == totalStudents &&
                  (!bestResult['success'] ||
                      efficiency > (bestResult['efficiency'] as double))) {
                bestSolution = List<Map<String, dynamic>>.from(combination);
                bestResult = {
                  ...simulationResult,
                  'efficiency': efficiency,
                  'success': true,
                };
                developer.log(
                    'Found better combination solution with efficiency: ${(efficiency * 100).toStringAsFixed(1)}%');
              }
            }
          }
        }

        // If still no solution, try combinations of 3 halls
        if (!bestResult['success']) {
          developer.log('Trying combinations of 3 halls...');
          for (var i = 0; i < availableHalls.length - 2; i++) {
            for (var j = i + 1; j < availableHalls.length - 1; j++) {
              for (var k = j + 1; k < availableHalls.length; k++) {
                final combination = [
                  availableHalls[i],
                  availableHalls[j],
                  availableHalls[k]
                ];
                final totalEffectiveCapacity = combination.fold<int>(
                    0, (sum, hall) => sum + calculateEffectiveHallCapacity(hall));

                if (totalEffectiveCapacity >= totalStudents) {
                  final simulationResult = simulateSeatingArrangement(
                    combination,
                    totalStudents,
                    widget.exams.where((e) => e['session'] == session).toList(),
                  );

                  final efficiency =
                      simulationResult['seated_count'] / totalEffectiveCapacity;

                  if (simulationResult['seated_count'] == totalStudents &&
                      (!bestResult['success'] ||
                          efficiency > (bestResult['efficiency'] as double))) {
                    bestSolution = List<Map<String, dynamic>>.from(combination);
                    bestResult = {
                      ...simulationResult,
                      'efficiency': efficiency,
                      'success': true,
                    };
                  }
                }
              }
            }
          }
        }
      }

      // Select the best solution found
      if (bestResult['success']) {
        for (final hall in bestSolution) {
          final hallId = hall['hall_id'].toString();
          developer.log('Selecting hall $hallId for session $session');
          newSelections[session]!.add(hallId);
        }

        final totalEffectiveCapacity = bestSolution.fold<int>(
            0, (sum, hall) => sum + calculateEffectiveHallCapacity(hall));
        developer.log(
            'Selected ${bestSolution.length} halls with efficiency: ${(bestResult['efficiency'] as double * 100).toStringAsFixed(1)}%');
      } else {
        developer.log('No suitable solution found for session $session');
      }
    }

    // Update the state with new selections
    setState(() {
      _selectedHallsBySession = Map<String, Set<String>>.from(newSelections);
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
                                          .surfaceVariant,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 1200
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
                                          onChanged: (value) => _selectHall(
                                              hallId, value ?? false),
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
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Selected Halls',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_selectedSession != null)
                                Text(
                                  '${_selectedHallsBySession[_selectedSession]?.length ?? 0} halls for ${_getSessionDisplayName(_selectedSession!)} session',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
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
                                  final allSelectedHallsWithSessions =
                                      <Map<String, dynamic>>[];

                                  // Iterate through each session and its halls
                                  for (final sessionEntry
                                      in _selectedHallsBySession.entries) {
                                    final session = sessionEntry.key;
                                    final hallIds = sessionEntry.value;

                                    // For each hall in this session
                                    for (final hallId in hallIds) {
                                      // Find the hall details
                                      final hall = _halls.firstWhere(
                                        (h) =>
                                            h['hall_id'].toString() == hallId,
                                        orElse: () => <String, dynamic>{},
                                      );

                                      if (hall.isNotEmpty) {
                                        allSelectedHallsWithSessions.add({
                                          ...hall,
                                          'session': session,
                                          'exam_date':
                                              _capacityNeededPerDateAndSession
                                                  .entries.first.key,
                                        });
                                      }
                                    }
                                  }

                                  developer
                                      .log('Selected halls with sessions:');
                                  for (final hall
                                      in allSelectedHallsWithSessions) {
                                    developer.log(
                                        'Hall ${hall['hall_id']} - Session: ${hall['session']} - Date: ${hall['exam_date']}');
                                  }

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SelectFacultyPage(
                                        exams: widget.exams,
                                        selectedStudents:
                                            widget.selectedStudents,
                                        selectedHalls:
                                            allSelectedHallsWithSessions,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
