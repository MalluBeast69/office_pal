import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/faculty/presentation/pages/faculty_dashboard_page.dart';
import 'package:office_pal/features/student/presentation/pages/student_dashboard_page.dart';
import 'package:office_pal/features/auth/presentation/pages/admin_login_page.dart';
import 'dart:math' as math;

enum LoginMode { student, faculty }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isObscured = true;
  LoginMode _loginMode = LoginMode.student;
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  late AnimationController _animationController;
  late AnimationController _gradientController;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _gradientAnimation;
  bool _isHoveringStudent = false;
  bool _isHoveringFaculty = false;
  bool _isIdFieldFocused = false;
  bool _isPasswordFieldFocused = false;

  @override
  void initState() {
    super.initState();
    // Main animation controller for one-time animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Separate controller for looping gradient
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 15000),
    )..repeat();

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
      ),
    );

    _slideAnimation = Tween<double>(
      begin: -100.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_gradientController);

    _animationController.forward();
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    _gradientController.dispose();
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
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    FacultyDashboardPage(
                  facultyId: id.toUpperCase(),
                  facultyName: data['faculty_name'],
                  departmentId: data['dept_id'],
                ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
              ),
            );
          }
        } else {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    StudentDashboardPage(
                  studentRegNo: id.toUpperCase(),
                  studentName: data['student_name'],
                  departmentId: data['dept_id'],
                  semester: data['semester'],
                ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
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
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _gradientAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: AnimatedGradientPainter(
                  animation: _gradientAnimation.value,
                  colorOne:
                      Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  colorTwo:
                      Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                ),
                size: MediaQuery.of(context).size,
              );
            },
          ),
          // Main content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 3D rotating logo
                  AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(_rotationAnimation.value),
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.9),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.school,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  // Welcome text with slide animation
                  AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_slideAnimation.value, 0),
                        child: child,
                      );
                    },
                    child: Text(
                      'Welcome Back!',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Login card
                  AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: child,
                      );
                    },
                    child: Card(
                      elevation: 8,
                      shadowColor:
                          Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Enhanced login mode toggle
                              Row(
                                children: [
                                  Expanded(
                                    child: MouseRegion(
                                      onEnter: (_) => setState(
                                          () => _isHoveringStudent = true),
                                      onExit: (_) => setState(
                                          () => _isHoveringStudent = false),
                                      child: GestureDetector(
                                        onTap: () => setState(() =>
                                            _loginMode = LoginMode.student),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          decoration: BoxDecoration(
                                            color:
                                                _loginMode == LoginMode.student
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              if (_loginMode ==
                                                      LoginMode.student ||
                                                  _isHoveringStudent)
                                                BoxShadow(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.school,
                                                color: _loginMode ==
                                                        LoginMode.student
                                                    ? Colors.white
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                size: 28,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Student',
                                                style: TextStyle(
                                                  color: _loginMode ==
                                                          LoginMode.student
                                                      ? Colors.white
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: MouseRegion(
                                      onEnter: (_) => setState(
                                          () => _isHoveringFaculty = true),
                                      onExit: (_) => setState(
                                          () => _isHoveringFaculty = false),
                                      child: GestureDetector(
                                        onTap: () => setState(() =>
                                            _loginMode = LoginMode.faculty),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          decoration: BoxDecoration(
                                            color:
                                                _loginMode == LoginMode.faculty
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              if (_loginMode ==
                                                      LoginMode.faculty ||
                                                  _isHoveringFaculty)
                                                BoxShadow(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.person_2,
                                                color: _loginMode ==
                                                        LoginMode.faculty
                                                    ? Colors.white
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                size: 28,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Faculty',
                                                style: TextStyle(
                                                  color: _loginMode ==
                                                          LoginMode.faculty
                                                      ? Colors.white
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Enhanced ID field with glow
                              Focus(
                                onFocusChange: (hasFocus) => setState(
                                    () => _isIdFieldFocused = hasFocus),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      if (_isIdFieldFocused)
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.2),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                  child: TextFormField(
                                    controller: _idController,
                                    decoration: InputDecoration(
                                      labelText: _getIdLabel,
                                      prefixIcon:
                                          const Icon(Icons.person_outline),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withOpacity(0.8),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your ${_getIdLabel.toLowerCase()}';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Enhanced password field with glow
                              Focus(
                                onFocusChange: (hasFocus) => setState(
                                    () => _isPasswordFieldFocused = hasFocus),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      if (_isPasswordFieldFocused)
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.2),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                  child: TextFormField(
                                    controller: _passwordController,
                                    obscureText: _isObscured,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isObscured
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () {
                                          setState(
                                              () => _isObscured = !_isObscured);
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withOpacity(0.8),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Sign in button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _signIn,
                                  style: ElevatedButton.styleFrom(
                                    elevation: 4,
                                    shadowColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? LoadingAnimationWidget
                                          .staggeredDotsWave(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          size: 24,
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Admin login button with hover effect
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        const AdminLoginPage(),
                                transitionsBuilder: (context, animation,
                                    secondaryAnimation, child) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.5),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.admin_panel_settings,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Login as Controller or Superintendent',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _idController.clear();
    _passwordController.clear();
  }
}

// Custom painter for animated background patterns
class BackgroundPatternPainter extends CustomPainter {
  final Color color;

  BackgroundPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const spacing = 30.0;
    final xCount = (size.width / spacing).ceil();
    final yCount = (size.height / spacing).ceil();

    for (var i = 0; i < xCount; i++) {
      for (var j = 0; j < yCount; j++) {
        final x = i * spacing;
        final y = j * spacing;
        final rect = Rect.fromLTWH(x, y, spacing, spacing);
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedGradientPainter extends CustomPainter {
  final double animation;
  final Color colorOne;
  final Color colorTwo;

  AnimatedGradientPainter({
    required this.animation,
    required this.colorOne,
    required this.colorTwo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(
          math.cos(animation) * 1.5,
          math.sin(animation) * 1.5,
        ),
        end: Alignment(
          math.cos(animation + math.pi) * 1.5,
          math.sin(animation + math.pi) * 1.5,
        ),
        colors: [
          colorOne,
          colorOne.withOpacity(0.6),
          colorTwo,
          colorTwo.withOpacity(0.6),
          colorOne,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant AnimatedGradientPainter oldDelegate) {
    return animation != oldDelegate.animation ||
        colorOne != oldDelegate.colorOne ||
        colorTwo != oldDelegate.colorTwo;
  }
}
