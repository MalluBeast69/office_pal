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
  Set<String> _selectedHalls = {};
  int _totalCapacityNeeded = 0;
  int _selectedCapacity = 0;

  @override
  void initState() {
    super.initState();
    _totalCapacityNeeded = widget.selectedStudents.length;
    _loadHalls();
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

  List<Map<String, dynamic>> _filterHalls() {
    return _halls.where((hall) {
      // Search filter
      final hallId = hall['hall_id']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      return hallId.contains(searchLower);
    }).toList();
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

  @override
  Widget build(BuildContext context) {
    final filteredHalls = _filterHalls();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Halls'),
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.select_all,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              'Select Available',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            onPressed: () {
              // Sort halls by capacity in descending order
              final sortedHalls = List<Map<String, dynamic>>.from(filteredHalls)
                ..sort((a, b) =>
                    (b['capacity'] as int).compareTo(a['capacity'] as int));

              int remainingCapacity = _totalCapacityNeeded;
              _selectedHalls.clear();
              _selectedCapacity = 0;

              // Select halls until we have enough capacity
              for (final hall in sortedHalls) {
                if (remainingCapacity <= 0) break;
                final capacity = hall['capacity'] as int;
                _selectHall(hall['hall_id'], true);
                remainingCapacity -= capacity;
              }
              setState(() {});
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _selectedCapacity >= _totalCapacityNeeded
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedCapacity >= _totalCapacityNeeded
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedCapacity >= _totalCapacityNeeded
                            ? Icons.check_circle
                            : Icons.warning,
                        color: _selectedCapacity >= _totalCapacityNeeded
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Capacity: $_selectedCapacity / $_totalCapacityNeeded',
                        style: TextStyle(
                          color: _selectedCapacity >= _totalCapacityNeeded
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
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
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredHalls.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final hall = filteredHalls[index];
                      final hallId = hall['hall_id'];
                      final isSelected = _selectedHalls.contains(hallId);

                      return Card(
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) =>
                              _selectHall(hallId, value ?? false),
                          title: Text(hallId),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Department: ${hall['hall_dept']}'),
                              Text(
                                  'Capacity: ${hall['capacity']} (${hall['no_of_columns']} columns × ${hall['no_of_rows']} rows)'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
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
                                _selectedCapacity < _totalCapacityNeeded
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SelectFacultyPage(
                                      exams: widget.exams,
                                      selectedStudents: widget.selectedStudents,
                                      selectedHalls: _selectedHalls.toList(),
                                    ),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
