import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:developer' as developer;

class FacultyManagementPage extends ConsumerStatefulWidget {
  final String? initialDepartment;

  const FacultyManagementPage({
    super.key,
    this.initialDepartment,
  });

  @override
  ConsumerState<FacultyManagementPage> createState() =>
      _FacultyManagementPageState();
}

class _FacultyManagementPageState extends ConsumerState<FacultyManagementPage> {
  List<Map<String, dynamic>> facultyList = [];
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> filteredFacultyList = [];
  bool isLoading = false;

  // Filter states
  String? selectedDepartment;
  bool? selectedAvailability;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedDepartment = widget.initialDepartment;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      filteredFacultyList = facultyList.where((faculty) {
        bool matchesDepartment = selectedDepartment == null ||
            faculty['dept_id'] == selectedDepartment;

        bool matchesAvailability = selectedAvailability == null ||
            faculty['is_available'] == selectedAvailability;

        bool matchesSearch = searchQuery.isEmpty ||
            faculty['faculty_name']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            faculty['faculty_id']
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase());

        return matchesDepartment && matchesAvailability && matchesSearch;
      }).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final facultyResponse = await Supabase.instance.client
          .from('faculty')
          .select()
          .order('faculty_name');

      final departmentsResponse = await Supabase.instance.client
          .from('departments')
          .select()
          .order('dept_name');

      if (mounted) {
        setState(() {
          facultyList = List<Map<String, dynamic>>.from(facultyResponse);
          departments = List<Map<String, dynamic>>.from(departmentsResponse);
          _applyFilters();
          isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $error'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _addFaculty() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        departments: departments,
        onSave: (newFaculty) async {
          try {
            setState(() => isLoading = true);
            await Supabase.instance.client.from('faculty').insert(newFaculty);

            if (mounted) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Faculty added successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _loadData();
            }
          } catch (error) {
            if (mounted) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Error adding faculty: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() => isLoading = false);
            }
          }
        },
      ),
    );
  }

  Future<void> _editFaculty(Map<String, dynamic> faculty) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FacultyDialog(
        faculty: faculty,
        departments: departments,
        onSave: (updatedFaculty) async {
          try {
            setState(() => isLoading = true);
            await Supabase.instance.client
                .from('faculty')
                .update(updatedFaculty)
                .eq('faculty_id', faculty['faculty_id']);

            if (mounted) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Faculty updated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _loadData();
            }
          } catch (error) {
            if (mounted) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Error updating faculty: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() => isLoading = false);
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleFacultyStatus(Map<String, dynamic> faculty) async {
    setState(() => isLoading = true);
    try {
      await Supabase.instance.client
          .from('faculty')
          .update({'is_available': !faculty['is_available']}).eq(
              'faculty_id', faculty['faculty_id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            faculty['is_available']
                ? 'Faculty marked as unavailable'
                : 'Faculty marked as available',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating faculty status: $error'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _importFromCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        developer.log('CSV file picked');
        final fileBytes = result.files.first.bytes;
        if (fileBytes == null) {
          throw Exception('No file content found');
        }

        final csvString = String.fromCharCodes(fileBytes);
        final rows = csvString.split('\n');
        if (rows.isEmpty) {
          throw Exception('CSV file is empty');
        }

        // Get headers from first row and normalize them
        final headers = rows[0]
            .split(',')
            .map((header) => header.trim().toLowerCase())
            .toList();
        final requiredHeaders = ['faculty_id', 'faculty_name', 'dept_id'];

        // Validate headers
        for (final header in requiredHeaders) {
          if (!headers.contains(header)) {
            throw Exception('Missing required column: $header');
          }
        }

        // Start processing from row 1 (skip headers)
        setState(() => isLoading = true);
        int successCount = 0;
        int errorCount = 0;
        final List<String> errors = [];

        for (int i = 1; i < rows.length; i++) {
          try {
            if (rows[i].trim().isEmpty) continue; // Skip empty rows

            final columns = rows[i].split(',');
            if (columns.length != headers.length) {
              throw Exception('Invalid number of columns');
            }

            final facultyData = {
              'faculty_id': columns[headers.indexOf('faculty_id')].trim(),
              'faculty_name': columns[headers.indexOf('faculty_name')].trim(),
              'dept_id': columns[headers.indexOf('dept_id')].trim(),
              'is_available': true,
            };

            // Validate data
            final facultyId = facultyData['faculty_id'] as String;
            final facultyName = facultyData['faculty_name'] as String;
            final deptId = facultyData['dept_id'] as String;

            if (facultyId.isEmpty) {
              throw Exception('Faculty ID cannot be empty');
            }
            if (facultyName.isEmpty) {
              throw Exception('Faculty name cannot be empty');
            }
            if (deptId.isEmpty) {
              throw Exception('Department ID cannot be empty');
            }

            // Validate department exists
            final deptExists =
                departments.any((d) => d['dept_id'] == facultyData['dept_id']);
            if (!deptExists) {
              throw Exception(
                  'Department ${facultyData['dept_id']} does not exist');
            }

            await Supabase.instance.client.from('faculty').insert(facultyData);
            successCount++;
          } catch (e) {
            errorCount++;
            errors.add('Row ${i + 1}: $e');
            developer.log('Error processing row ${i + 1}: $e');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Import completed: $successCount successful, $errorCount failed',
              ),
              backgroundColor: errorCount == 0 ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 5),
              action: errorCount > 0
                  ? SnackBarAction(
                      label: 'Show Errors',
                      textColor: Colors.white,
                      onPressed: () => _showErrorDialog(errors),
                    )
                  : null,
            ),
          );
          _loadData();
        }
      }
    } catch (error) {
      developer.log('Error importing CSV: $error');
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

  void _showErrorDialog(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Errors'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: errors
                .map((error) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ))
                .toList(),
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
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Management'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallScreen ? 8.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Faculty List',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 20 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _importFromCsv,
                          icon: const Icon(Icons.upload_file),
                          label: Text(
                            'Import CSV',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _addFaculty,
                          icon: const Icon(Icons.add),
                          label: Text(
                            'Add Faculty',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Search and Filter Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filters',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 16 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Search TextField
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                labelText: 'Search faculty',
                                hintText: 'Enter name or ID',
                                prefixIcon: const Icon(Icons.search),
                                border: const OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: isSmallScreen ? 8 : 16,
                                  vertical: isSmallScreen ? 8 : 16,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  searchQuery = value;
                                  _applyFilters();
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            // Filter Options
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                // Department Filter
                                DropdownButton<String>(
                                  value: selectedDepartment,
                                  hint: const Text('Select Department'),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('All Departments'),
                                    ),
                                    ...departments.map((dept) {
                                      return DropdownMenuItem<String>(
                                        value: dept['dept_id'],
                                        child: Text(dept['dept_name']),
                                      );
                                    }),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      selectedDepartment = value;
                                      _applyFilters();
                                    });
                                  },
                                ),
                                // Availability Filter
                                DropdownButton<bool?>(
                                  value: selectedAvailability,
                                  hint: const Text('Select Availability'),
                                  items: const [
                                    DropdownMenuItem<bool?>(
                                      value: null,
                                      child: Text('All Status'),
                                    ),
                                    DropdownMenuItem<bool?>(
                                      value: true,
                                      child: Text('Available'),
                                    ),
                                    DropdownMenuItem<bool?>(
                                      value: false,
                                      child: Text('Unavailable'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      selectedAvailability = value;
                                      _applyFilters();
                                    });
                                  },
                                ),
                                // Clear Filters Button
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      selectedDepartment = null;
                                      selectedAvailability = null;
                                      searchQuery = '';
                                      _searchController.clear();
                                      _applyFilters();
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear Filters'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Faculty List
                    if (filteredFacultyList.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No faculty members found'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredFacultyList.length,
                        itemBuilder: (context, index) {
                          final faculty = filteredFacultyList[index];
                          final department = departments.firstWhere(
                            (d) => d['dept_id'] == faculty['dept_id'],
                            orElse: () => {'dept_name': 'Unknown'},
                          );
                          return Card(
                            child: ListTile(
                              title: Text(faculty['faculty_name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ID: ${faculty['faculty_id']}\n'
                                    'Department: ${department['dept_name']}',
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: faculty['is_available'] == true
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: faculty['is_available'] == true
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                    child: Text(
                                      faculty['is_available'] == true
                                          ? 'Available'
                                          : 'Unavailable',
                                      style: TextStyle(
                                        color: faculty['is_available'] == true
                                            ? Colors.green
                                            : Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editFaculty(faculty),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class FacultyDialog extends StatefulWidget {
  final Map<String, dynamic>? faculty;
  final List<Map<String, dynamic>> departments;
  final Function(Map<String, dynamic>) onSave;

  const FacultyDialog({
    super.key,
    this.faculty,
    required this.departments,
    required this.onSave,
  });

  @override
  State<FacultyDialog> createState() => _FacultyDialogState();
}

class _FacultyDialogState extends State<FacultyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDepartment;
  bool _isAvailable = true;

  @override
  void initState() {
    super.initState();
    if (widget.faculty != null) {
      _idController.text = widget.faculty!['faculty_id'];
      _nameController.text = widget.faculty!['faculty_name'];
      _selectedDepartment = widget.faculty!['dept_id'];
      _isAvailable = widget.faculty!['is_available'] ?? true;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Dialog(
      child: Container(
        width: isSmallScreen ? screenSize.width * 0.9 : 500,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.faculty == null ? 'Add Faculty' : 'Edit Faculty',
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Faculty ID',
                  border: OutlineInputBorder(),
                ),
                enabled: widget.faculty == null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter faculty ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Faculty Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter faculty name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                items: widget.departments.map((dept) {
                  return DropdownMenuItem<String>(
                    value: dept['dept_id'],
                    child: Text(dept['dept_name']),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() => _selectedDepartment = value);
                },
              ),
              const SizedBox(height: 16),
              // Availability Switch
              SwitchListTile(
                title: const Text('Available'),
                value: _isAvailable,
                onChanged: (value) {
                  setState(() => _isAvailable = value);
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSave({
                          'faculty_id': _idController.text,
                          'faculty_name': _nameController.text,
                          'dept_id': _selectedDepartment,
                          'is_available': _isAvailable,
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
