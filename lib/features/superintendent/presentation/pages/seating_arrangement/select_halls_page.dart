import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'select_faculty_page.dart';

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
  final Set<String> _selectedHalls = {};
  Map<String, int> _capacityNeededPerSession = {};
  int _maxCapacityNeeded = 0;
  int _selectedCapacity = 0;
  String? _selectedDepartment;
  List<String> _departments = [];

  @override
  void initState() {
    super.initState();
    _calculateCapacityNeeds();
    _loadHalls();
  }

  void _calculateCapacityNeeds() {
    // Group students by exam session
    final studentsBySession = <String, Set<String>>{};

    for (final exam in widget.exams) {
      final session = exam['session'] as String;
      studentsBySession[session] ??= {};

      // Add students for this exam to the session's set
      for (final studentId in widget.selectedStudents) {
        studentsBySession[session]!.add(studentId);
      }
    }

    // Calculate capacity needed for each session
    _capacityNeededPerSession = {
      for (var entry in studentsBySession.entries) entry.key: entry.value.length
    };

    // Find the maximum capacity needed across all sessions
    _maxCapacityNeeded = _capacityNeededPerSession.values.fold(
      0,
      (max, count) => count > max ? count : max,
    );
  }

  Future<void> _loadHalls() async {
    try {
      setState(() => _isLoading = true);
      final response = await Supabase.instance.client
          .from('hall')
          .select()
          .eq('availability', true);

      if (mounted) {
        setState(() {
          _halls = List<Map<String, dynamic>>.from(response);
          _departments = _halls
              .map((h) => h['hall_dept'] as String)
              .toSet()
              .toList()
            ..sort();
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading halls: $error'),
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

  void _selectHall(String hallId, bool selected) {
    final hall = _halls.firstWhere((h) => h['hall_id'] == hallId);
    setState(() {
      if (selected) {
        _selectedHalls.add(hallId);
        _selectedCapacity += hall['capacity'] as int;
      } else {
        _selectedHalls.remove(hallId);
        _selectedCapacity -= hall['capacity'] as int;
      }
    });
  }

  void _autoSelectHalls() {
    // Clear current selection
    _selectedHalls.clear();
    _selectedCapacity = 0;

    // Get filtered and sorted halls
    final availableHalls = _filterAndSortHalls();

    // Calculate needed capacity with 5% buffer (reduced from 10% since we're being more efficient)
    final targetCapacity = (_maxCapacityNeeded * 1.05).ceil();
    int remainingCapacity = targetCapacity;

    // Group halls by department
    final hallsByDept = <String, List<Map<String, dynamic>>>{};
    for (final hall in availableHalls) {
      final dept = hall['hall_dept'] as String;
      hallsByDept[dept] ??= [];
      hallsByDept[dept]!.add(hall);
    }

    // Sort departments by total capacity (descending)
    final sortedDepts = hallsByDept.entries.toList()
      ..sort((a, b) {
        final aCapacity =
            a.value.fold(0, (sum, hall) => sum + (hall['capacity'] as int));
        final bCapacity =
            b.value.fold(0, (sum, hall) => sum + (hall['capacity'] as int));
        return bCapacity.compareTo(aCapacity);
      });

    // Try to find optimal halls from departments
    for (final deptEntry in sortedDepts) {
      final halls = deptEntry.value;
      var currentCapacity = 0;
      var selectedFromDept = <Map<String, dynamic>>[];

      // Sort halls by capacity (descending)
      halls.sort(
          (a, b) => (b['capacity'] as int).compareTo(a['capacity'] as int));

      // Try to find optimal combination of halls
      for (final hall in halls) {
        final capacity = hall['capacity'] as int;

        // If this hall would exceed our target by too much, skip it
        if (currentCapacity > 0 &&
            currentCapacity + capacity > targetCapacity * 1.2) {
          continue;
        }

        currentCapacity += capacity;
        selectedFromDept.add(hall);

        // If we have enough capacity with good efficiency, use these halls
        if (currentCapacity >= targetCapacity &&
            currentCapacity <= targetCapacity * 1.2) {
          for (final selected in selectedFromDept) {
            _selectHall(selected['hall_id'], true);
          }
          return;
        }
      }

      // If we found a reasonable solution in this department, use it
      if (currentCapacity >= targetCapacity) {
        for (final selected in selectedFromDept) {
          _selectHall(selected['hall_id'], true);
        }
        return;
      }
    }

    // If we couldn't find an optimal solution in a single department,
    // select halls while trying to minimize department switches
    var currentCapacity = 0;
    for (final hall in availableHalls) {
      final capacity = hall['capacity'] as int;

      // Skip if this hall would exceed our target by too much
      if (currentCapacity > 0 &&
          currentCapacity + capacity > targetCapacity * 1.2) {
        continue;
      }

      _selectHall(hall['hall_id'], true);
      currentCapacity += capacity;

      if (currentCapacity >= targetCapacity) {
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredHalls = _filterAndSortHalls();

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
              onPressed: _autoSelectHalls,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(220),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
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
                    color: _selectedCapacity >= _maxCapacityNeeded
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedCapacity >= _maxCapacityNeeded
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedCapacity >= _maxCapacityNeeded
                                ? Icons.check_circle
                                : Icons.warning,
                            color: _selectedCapacity >= _maxCapacityNeeded
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Max Capacity Needed: $_maxCapacityNeeded',
                            style: TextStyle(
                              color: _selectedCapacity >= _maxCapacityNeeded
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Selected Capacity: $_selectedCapacity',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children:
                            _capacityNeededPerSession.entries.map((entry) {
                          return Chip(
                            label: Text(
                              '${entry.key}: ${entry.value}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceVariant,
                          );
                        }).toList(),
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
                        final isSelected = _selectedHalls.contains(hallId);

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
                          child: Text(
                            'Selected: ${_selectedHalls.length} halls',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                          onPressed: _selectedHalls.isEmpty ||
                                  _selectedCapacity < _maxCapacityNeeded
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SelectFacultyPage(
                                        exams: widget.exams,
                                        selectedStudents:
                                            widget.selectedStudents,
                                        selectedHalls: _selectedHalls.toList(),
                                      ),
                                    ),
                                  );
                                },
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
