import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/auth/presentation/pages/superintendent_login_page.dart';

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

  void _navigateToSuperintendentLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SuperintendentLoginPage(),
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    // Check if password matches ID
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
          .eq(idField,
              id.toUpperCase()); // Convert ID to uppercase to match database

      final data = await query.single();

      if (mounted && data != null) {
        // Successfully found the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome ${data[nameField]}!'),
            backgroundColor: Colors.green,
          ),
        );
        // TODO: Navigate to appropriate home page with user data
        // For student:
        // - data['student_name']
        // - data['dept_id']
        // - data['semester']
        // For faculty:
        // - data['faculty_name']
        // - data['dept_id']
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        String errorMessage;
        if (error.code == 'PGRST116') {
          // No rows returned
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
                        // Clear the form when switching modes
                        _idController.clear();
                        _passwordController.clear();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: _loginMode == LoginMode.student
                        ? 'Registration Number'
                        : 'Faculty ID',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return _loginMode == LoginMode.student
                          ? 'Please enter your registration number'
                          : 'Please enter your faculty ID';
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
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _navigateToSuperintendentLogin,
                    child: const Text(
                      'Login as Superintendent?',
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
}
