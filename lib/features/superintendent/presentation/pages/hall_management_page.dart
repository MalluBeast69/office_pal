import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class HallManagementPage extends ConsumerStatefulWidget {
  const HallManagementPage({super.key});

  @override
  ConsumerState<HallManagementPage> createState() => _HallManagementPageState();
}

class _HallManagementPageState extends ConsumerState<HallManagementPage>
    with TickerProviderStateMixin {
  bool isLoading = false;
  bool isInitializing = true;
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
  final _noOfRowsController = TextEditingController();

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  // Current section for sidebar
  String _currentSection = 'all';

  @override
  void initState() {
    super.initState();

    // Initialize with shorter animations for better performance
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start animations
    _fadeInController.forward();
    _slideController.forward();

    _loadHalls();
  }

  @override
  void dispose() {
    _hallIdController.dispose();
    _hallDeptController.dispose();
    _noOfColumnsController.dispose();
    _capacityController.dispose();
    _noOfRowsController.dispose();
    _fadeInController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      selectedDepartment = null;
      availabilityFilter = null;
      _currentSection = 'all';
      filteredHalls = List.from(halls);
    });
  }

  void _applyFilters() {
    // Optimize filtering by checking if any filters are active
    final hasActiveFilters =
        selectedDepartment != null || availabilityFilter != null;

    if (!hasActiveFilters) {
      setState(() {
        filteredHalls = List.from(halls);
      });
      return;
    }

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

  Future<void> _loadHalls() async {
    setState(() {
      isLoading = true;
      isInitializing = true;
    });

    try {
      developer.log('Fetching from hall table...');
      final response =
          await Supabase.instance.client.from('hall').select().order('hall_id');

      if (mounted) {
        setState(() {
          halls = List<Map<String, dynamic>>.from(response);
          filteredHalls = List.from(halls);

          // Extract unique departments using Set for efficiency
          final deptSet = <String>{};
          for (final hall in halls) {
            deptSet.add(hall['hall_dept'].toString());
          }

          departments = deptSet.toList()..sort();
          isLoading = false;
          isInitializing = false;
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
        setState(() {
          isLoading = false;
          isInitializing = false;
        });
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
        setState(() => isLoading = true);

        final file = File(result.files.single.path!);
        final csvString = await file.readAsString();
        final rows = csvString.split('\n');

        developer.log('Processing CSV with ${rows.length} rows');

        // Skip header row and empty rows
        final dataRows = rows.sublist(1).where((row) => row.trim().isNotEmpty);

        for (var row in dataRows) {
          final columns = row.split(',');
          if (columns.length < 4) continue;

          final hallId = columns[0].trim();
          final hallDept = columns[1].trim();
          final noOfColumns = int.tryParse(columns[2].trim()) ?? 0;
          final noOfRows = int.tryParse(columns[3].trim()) ?? 0;
          final capacity = noOfColumns * noOfRows;

          developer.log('Adding hall: $hallId ($hallDept)');

          await Supabase.instance.client.from('hall').upsert({
            'hall_id': hallId,
            'hall_dept': hallDept,
            'no_of_columns': noOfColumns,
            'no_of_rows': noOfRows,
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

  void _clearForm() {
    _hallIdController.clear();
    _hallDeptController.clear();
    _noOfColumnsController.clear();
    _capacityController.clear();
    _noOfRowsController.clear();
  }

  void _showAddHallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Hall'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _hallIdController,
                decoration: InputDecoration(
                  labelText: 'Hall ID',
                  hintText: 'e.g., HALL001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.meeting_room),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter hall ID';
                  }
                  if (value.length > 20) {
                    return 'Hall ID must be less than 20 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hallDeptController,
                decoration: InputDecoration(
                  labelText: 'Department',
                  hintText: 'e.g., CSE',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.business),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department';
                  }
                  if (value.length > 10) {
                    return 'Department must be less than 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _noOfColumnsController,
                      decoration: InputDecoration(
                        labelText: 'Columns',
                        hintText: 'e.g., 5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.view_column),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter columns';
                        }
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _noOfRowsController,
                      decoration: InputDecoration(
                        labelText: 'Rows',
                        hintText: 'e.g., 6',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.view_week),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter rows';
                        }
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
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
            onPressed: _addHall,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addHall() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      final noOfColumns = int.parse(_noOfColumnsController.text);
      final noOfRows = int.parse(_noOfRowsController.text);
      final capacity = noOfColumns * noOfRows;

      await Supabase.instance.client.from('hall').insert({
        'hall_id': _hallIdController.text,
        'hall_dept': _hallDeptController.text,
        'no_of_columns': noOfColumns,
        'no_of_rows': noOfRows,
        'capacity': capacity,
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
        _clearForm();
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

  void _showEditHallDialog(Map<String, dynamic> hall) {
    _hallIdController.text = hall['hall_id'].toString();
    _hallDeptController.text = hall['hall_dept'].toString();
    _noOfColumnsController.text = hall['no_of_columns'].toString();
    _noOfRowsController.text = (hall['no_of_rows'] ?? '').toString();
    _capacityController.text = hall['capacity'].toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Hall'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _hallIdController,
                decoration: InputDecoration(
                  labelText: 'Hall ID',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.meeting_room),
                ),
                enabled: false,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hallDeptController,
                decoration: InputDecoration(
                  labelText: 'Department',
                  hintText: 'e.g., CSE',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.business),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter department';
                  }
                  if (value.length > 10) {
                    return 'Department must be less than 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _noOfColumnsController,
                      decoration: InputDecoration(
                        labelText: 'Columns',
                        hintText: 'e.g., 5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.view_column),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter columns';
                        }
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _noOfRowsController,
                      decoration: InputDecoration(
                        labelText: 'Rows',
                        hintText: 'e.g., 6',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.view_week),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter rows';
                        }
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
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
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateHall(String hallId) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      final noOfColumns = int.parse(_noOfColumnsController.text);
      final noOfRows = int.parse(_noOfRowsController.text);
      final capacity = noOfColumns * noOfRows;

      await Supabase.instance.client.from('hall').update({
        'hall_dept': _hallDeptController.text,
        'no_of_columns': noOfColumns,
        'no_of_rows': noOfRows,
        'capacity': capacity,
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

  Future<void> _toggleHallAvailability(String hallId, bool currentValue) async {
    try {
      await Supabase.instance.client
          .from('hall')
          .update({'availability': !currentValue}).eq('hall_id', hallId);

      // Update local state first for immediate UI feedback
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
      setState(() => isLoading = true);

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
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final theme = Theme.of(context);
    const isWeb = kIsWeb;

    return Scaffold(
      appBar: isSmallScreen
          ? AppBar(
              title: Text(
                'Hall Management',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              actions: [
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      ),
                    ),
                  )
              ],
            )
          : null,
      body: isInitializing
          ? _buildLoadingScreen()
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSmallScreen) _buildSidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          if (!isSmallScreen) _buildAppBar(theme, isWeb),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _loadHalls,
                              child: CustomScrollView(
                                slivers: [
                                  if (isInitializing)
                                    SliverFadeTransition(
                                      opacity: _fadeInAnimation,
                                      sliver: SliverToBoxAdapter(
                                        child: SlideTransition(
                                          position: _slideAnimation,
                                          child: _buildContent(isSmallScreen),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverToBoxAdapter(
                                      child: _buildContent(isSmallScreen),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      drawer: isSmallScreen
          ? Drawer(
              child: _buildSidebar(),
            )
          : null,
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade100,
            Colors.blue.shade50,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.blue,
              size: 50,
            ),
            const SizedBox(height: 24),
            Text(
              'Hall Management',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading halls...',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 280,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.meeting_room,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Halls',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Add Clear Filters button
            if (selectedDepartment != null || availabilityFilter != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear All Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    minimumSize: const Size(double.infinity, 40),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSidebarItem(
                      'all',
                      'All Halls',
                      Icons.meeting_room,
                      onTap: () {
                        setState(() {
                          _currentSection = 'all';
                          _resetFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSidebarItem(
                      'available',
                      'Available Halls',
                      Icons.check_circle_outline,
                      onTap: () {
                        setState(() {
                          _currentSection = 'available';
                          selectedDepartment = null;
                          availabilityFilter = true;
                          _applyFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSidebarItem(
                      'unavailable',
                      'Unavailable Halls',
                      Icons.cancel_outlined,
                      onTap: () {
                        setState(() {
                          _currentSection = 'unavailable';
                          selectedDepartment = null;
                          availabilityFilter = false;
                          _applyFilters();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'DEPARTMENTS',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...departments.map((dept) => _buildSidebarItem(
                          'dept_$dept',
                          dept,
                          Icons.business,
                          onTap: () {
                            setState(() {
                              _currentSection = 'dept_$dept';
                              selectedDepartment = dept;
                              availabilityFilter = null;
                              _applyFilters();
                            });
                          },
                        )),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: OutlinedButton.icon(
                onPressed: () {
                  // Navigate back to the dashboard
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.dashboard),
                label: const Text('Return to Dashboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  backgroundColor: Colors.blue.shade50,
                  minimumSize: const Size(double.infinity, 44),
                  side: BorderSide(color: Colors.blue.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    String id,
    String title,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    final isSelected = _currentSection == id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade50 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: Colors.blue.shade200) : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Colors.blue.shade700
                        : Colors.grey.shade800,
                  ),
                ),
              ),
              if (id.startsWith('dept_'))
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    halls
                        .where((h) => h['hall_dept'] == title)
                        .length
                        .toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.blue.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme, bool isWeb) {
    String title = 'Hall Management';

    if (_currentSection == 'available') {
      title = 'Available Halls';
    } else if (_currentSection == 'unavailable') {
      title = 'Unavailable Halls';
    } else if (_currentSection.startsWith('dept_')) {
      title = '${_currentSection.substring(5)} Department Halls';
    } else {
      title = 'All Halls';
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.primaryColor,
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _showAddHallDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Hall'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSmallScreen) _buildHeaderSection(),
          const SizedBox(height: 16),
          _buildFilterChips(),
          const SizedBox(height: 16),
          _buildHallsGrid(),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    // Build title based on active filters
    List<String> filterParts = [];

    if (selectedDepartment != null) {
      filterParts.add('Department: $selectedDepartment');
    }

    if (availabilityFilter != null) {
      filterParts.add(availabilityFilter! ? 'Available' : 'Unavailable');
    }

    String title =
        filterParts.isNotEmpty ? filterParts.join(', ') : 'All Halls';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${filteredHalls.length} halls',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import'),
                  onPressed: _importFromCSV,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Hall'),
                  onPressed: _showAddHallDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (selectedDepartment != null)
          FilterChip(
            label: Text('Department: $selectedDepartment'),
            onSelected: (_) {
              setState(() {
                selectedDepartment = null;
                _applyFilters();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                selectedDepartment = null;
                _applyFilters();
              });
            },
          ),
        if (availabilityFilter != null)
          FilterChip(
            label: Text(availabilityFilter! ? 'Available' : 'Unavailable'),
            onSelected: (_) {
              setState(() {
                availabilityFilter = null;
                _applyFilters();
              });
            },
            selected: true,
            showCheckmark: false,
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () {
              setState(() {
                availabilityFilter = null;
                _applyFilters();
              });
            },
          ),
      ],
    );
  }

  Widget _buildHallsGrid() {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (filteredHalls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.meeting_room_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No halls found',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            if (halls.isEmpty)
              FilledButton.icon(
                onPressed: _importFromCSV,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import from CSV'),
              ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: filteredHalls.length,
      itemBuilder: (context, index) {
        final hall = filteredHalls[index];
        return _buildHallCard(hall);
      },
    );
  }

  Widget _buildHallCard(Map<String, dynamic> hall) {
    final isAvailable = hall['availability'] ?? false;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isAvailable ? Colors.green.shade100 : Colors.red.shade100,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showEditHallDialog(hall),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hall ID and Availability
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      hall['hall_id'],
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: isAvailable,
                      onChanged: (value) => _toggleHallAvailability(
                          hall['hall_id'], hall['availability']),
                      activeColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      inactiveTrackColor: Colors.red.withOpacity(0.5),
                    ),
                  ),
                ],
              ),

              // Department
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hall['hall_dept'],
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const Spacer(),

              // Capacity info with bigger font
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${hall['capacity']}',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'seats',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),

              // Columns and Rows in smaller text
              Center(
                child: Text(
                  '${hall['no_of_columns']} × ${hall['no_of_rows'] ?? 'N/A'}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),

              const Spacer(),

              // Action buttons in a more compact form
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    color: Colors.blue,
                    tooltip: 'Edit Hall',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showEditHallDialog(hall),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: Colors.red,
                    tooltip: 'Delete Hall',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showDeleteConfirmation(hall),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> hall) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Hall'),
        content: Text('Are you sure you want to delete ${hall['hall_id']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
    );
  }
}
