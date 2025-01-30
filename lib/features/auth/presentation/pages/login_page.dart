import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/faculty/presentation/pages/faculty_dashboard_page.dart';
import 'package:office_pal/features/student/presentation/pages/student_dashboard_page.dart';
import 'package:office_pal/features/auth/presentation/pages/admin_login_page.dart';

enum LoginMode { student, faculty }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isObscured = true;
  LoginMode _loginMode = LoginMode.student;
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _getIdLabel {
    return _loginMode == LoginMode.student
        ? 'Registration Number'
        : 'Faculty ID';
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    // Check if password matches ID for students and faculty
    if (id != password) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _loginMode == LoginMode.student
                  ? 'Registration number and password must be the same'
                  : 'Faculty ID and password must be the same',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Query the appropriate table based on login mode
      final table = _loginMode == LoginMode.student ? 'student' : 'faculty';
      final idField =
          _loginMode == LoginMode.student ? 'student_reg_no' : 'faculty_id';
      final nameField =
          _loginMode == LoginMode.student ? 'student_name' : 'faculty_name';

      final query = Supabase.instance.client
          .from(table)
          .select(
              '$nameField, dept_id${_loginMode == LoginMode.student ? ", semester" : ""}')
          .eq(idField, id.toUpperCase());

      final data = await query.single();

      if (mounted && data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome ${data[nameField]}!'),
            backgroundColor: Colors.green,
          ),
        );

        if (_loginMode == LoginMode.faculty) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => FacultyDashboardPage(
                  facultyId: id.toUpperCase(),
                  facultyName: data['faculty_name'],
                  departmentId: data['dept_id'],
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => StudentDashboardPage(
                  studentRegNo: id.toUpperCase(),
                  studentName: data['student_name'],
                  departmentId: data['dept_id'],
                  semester: data['semester'],
                ),
              ),
            );
          }
        }
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        String errorMessage;
        if (error.code == 'PGRST116') {
          errorMessage = _loginMode == LoginMode.student
              ? 'Invalid registration number'
              : 'Invalid faculty ID';
        } else {
          errorMessage = 'Database error occurred';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An unexpected error occurred'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Login mode toggle
                Center(
                  child: SegmentedButton<LoginMode>(
                    segments: const [
                      ButtonSegment<LoginMode>(
                        value: LoginMode.student,
                        label: Text('Student'),
                        icon: Icon(Icons.school),
                      ),
                      ButtonSegment<LoginMode>(
                        value: LoginMode.faculty,
                        label: Text('Faculty'),
                        icon: Icon(Icons.person_2),
                      ),
                    ],
                    selected: {_loginMode},
                    onSelectionChanged: (Set<LoginMode> newSelection) {
                      setState(() {
                        _loginMode = newSelection.first;
                        _clearForm();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: _getIdLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your ${_getIdLabel.toLowerCase()}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _isObscured,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isObscured ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _isObscured = !_isObscured);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? LoadingAnimationWidget.staggeredDotsWave(
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const AdminLoginPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text(
                      'Login as Controller or Superintendent',
                      style: TextStyle(
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearForm() {
    _idController.clear();
    _passwordController.clear();
  }
}
