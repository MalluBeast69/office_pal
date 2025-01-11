import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:developer' as developer;

class HallManagementPage extends ConsumerStatefulWidget {
  const HallManagementPage({super.key});

  @override
  ConsumerState<HallManagementPage> createState() => _HallManagementPageState();
}

class _HallManagementPageState extends ConsumerState<HallManagementPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> halls = [];
  List<Map<String, dynamic>> filteredHalls = [];
  List<String> departments = [];
  String? selectedDepartment;
  bool? availabilityFilter;
  final _formKey = GlobalKey<FormState>();
  final _hallIdController = TextEditingController();
  final _hallDeptController = TextEditingController();
  final _noOfColumnsController = TextEditingController();
  final _capacityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHalls();
  }

  @override
  void dispose() {
    _hallIdController.dispose();
    _hallDeptController.dispose();
    _noOfColumnsController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      filteredHalls = halls.where((hall) {
        bool matchesDepartment = selectedDepartment == null ||
            hall['hall_dept'] == selectedDepartment;
        bool matchesAvailability = availabilityFilter == null ||
            hall['availability'] == availabilityFilter;
        return matchesDepartment && matchesAvailability;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      selectedDepartment = null;
      availabilityFilter = null;
      filteredHalls = List.from(halls);
    });
  }

  Future<void> _loadHalls() async {
    setState(() => isLoading = true);
    try {
      developer.log('Fetching from hall table...');
      final response =
          await Supabase.instance.client.from('hall').select().order('hall_id');

      if (mounted) {
        setState(() {
          halls = List<Map<String, dynamic>>.from(response);
          filteredHalls = List.from(halls);
          // Extract unique departments
          departments = halls
              .map((hall) => hall['hall_dept'].toString())
              .toSet()
              .toList()
            ..sort();
          isLoading = false;
        });
      }
    } catch (error, stackTrace) {
      developer.log(
        'Error loading halls',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading halls: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _importFromCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final csvString = await file.readAsString();
        final rows = csvString.split('\n');

        developer.log('Processing CSV with ${rows.length} rows');

        // Skip header row and empty rows
        final dataRows = rows.sublist(1).where((row) => row.trim().isNotEmpty);

        setState(() => isLoading = true);

        for (var row in dataRows) {
          final columns = row.split(',');
          if (columns.length < 4) continue;

          final hallId = columns[0].trim();
          final hallDept = columns[1].trim();
          final noOfColumns = int.tryParse(columns[2].trim()) ?? 0;
          final capacity = int.tryParse(columns[3].trim()) ?? 0;

          developer.log('Adding hall: $hallId ($hallDept)');

          await Supabase.instance.client.from('hall').upsert({
            'hall_id': hallId,
            'hall_dept': hallDept,
            'no_of_columns': noOfColumns,
            'capacity': capacity,
            'availability': true,
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV imported successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadHalls();
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'Error importing CSV',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing CSV: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _addHall() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      await Supabase.instance.client.from('hall').insert({
        'hall_id': _hallIdController.text,
        'hall_dept': _hallDeptController.text,
        'no_of_columns': 0,
        'capacity': 0,
        'availability': true,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hall added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadHalls();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding hall: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _showAddHallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Hall'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _hallIdController,
                decoration: const InputDecoration(labelText: 'Hall ID'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter hall ID';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _hallDeptController,
                decoration: const InputDecoration(labelText: 'Department'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _addHall,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleHallAvailability(String hallId, bool currentValue) async {
    try {
      await Supabase.instance.client
          .from('hall')
          .update({'availability': !currentValue}).eq('hall_id', hallId);

      // Update local state first
      setState(() {
        final hallIndex = halls.indexWhere((h) => h['hall_id'] == hallId);
        if (hallIndex != -1) {
          halls[hallIndex]['availability'] = !currentValue;
          // Reapply filters to maintain current filter state
          _applyFilters();
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating hall availability: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteHall(String hallId) async {
    try {
      // Delete column details first due to foreign key constraint
      await Supabase.instance.client
          .from('column_details')
          .delete()
          .eq('hall_id', hallId);

      // Then delete the hall
      await Supabase.instance.client
          .from('hall')
          .delete()
          .eq('hall_id', hallId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hall deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadHalls();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting hall: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditHallDialog(Map<String, dynamic> hall) {
    _hallIdController.text = hall['hall_id'].toString();
    _hallDeptController.text = hall['hall_dept'].toString();
    _noOfColumnsController.text = hall['no_of_columns'].toString();
    _capacityController.text = hall['capacity'].toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Hall'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _hallIdController,
                decoration: const InputDecoration(labelText: 'Hall ID'),
                enabled: false, // Hall ID cannot be edited
              ),
              TextFormField(
                controller: _hallDeptController,
                decoration: const InputDecoration(labelText: 'Department'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _noOfColumnsController,
                decoration:
                    const InputDecoration(labelText: 'Number of Columns'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter number of columns';
                  }
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(labelText: 'Capacity'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter capacity';
                  }
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _clearForm();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _updateHall(hall['hall_id']),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _hallIdController.clear();
    _hallDeptController.clear();
    _noOfColumnsController.clear();
    _capacityController.clear();
  }

  Future<void> _updateHall(String hallId) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      await Supabase.instance.client.from('hall').update({
        'hall_dept': _hallDeptController.text,
        'no_of_columns': int.parse(_noOfColumnsController.text),
        'capacity': int.parse(_capacityController.text),
      }).eq('hall_id', hallId);

      if (mounted) {
        _clearForm();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hall updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadHalls();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating hall: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hall Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddHallDialog,
            tooltip: 'Add Hall',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedDepartment,
                            decoration: const InputDecoration(
                              labelText: 'Department',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Departments'),
                              ),
                              ...departments.map((dept) => DropdownMenuItem(
                                    value: dept,
                                    child: Text(dept),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedDepartment = value;
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<bool?>(
                            value: availabilityFilter,
                            decoration: const InputDecoration(
                              labelText: 'Availability',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('All'),
                              ),
                              DropdownMenuItem(
                                value: true,
                                child: Text('Available'),
                              ),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Not Available'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                availabilityFilter = value;
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: () {
                            _resetFilters();
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Halls list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredHalls.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'No halls found',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 16),
                            if (halls
                                .isEmpty) // Show import button only if no halls exist
                              FilledButton.icon(
                                onPressed: _importFromCSV,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Import from CSV'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredHalls.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final hall = filteredHalls[index];

                          return Card(
                            child: ListTile(
                              title: Text(hall['hall_id']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Department: ${hall['hall_dept']}'),
                                  Text('Columns: ${hall['no_of_columns']}'),
                                  Text('Capacity: ${hall['capacity']}'),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: hall['availability'] ?? false,
                                    onChanged: (value) =>
                                        _toggleHallAvailability(hall['hall_id'],
                                            hall['availability']),
                                    activeColor: Colors.green,
                                    inactiveThumbColor: Colors.red,
                                    inactiveTrackColor:
                                        Colors.red.withOpacity(0.5),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    color: Colors.blue,
                                    onPressed: () => _showEditHallDialog(hall),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Hall'),
                                        content: Text(
                                            'Are you sure you want to delete ${hall['hall_id']}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteHall(hall['hall_id']);
                                            },
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
