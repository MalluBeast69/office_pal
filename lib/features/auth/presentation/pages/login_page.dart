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

  // Animation controllers
  late AnimationController _fadeInController;
  late AnimationController _slideController;
  late AnimationController _featureCarouselController;

  // Animations
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _featureOpacityAnimation;

  // Current feature index
  int _currentFeatureIndex = 0;

  // List of features to display in carousel
  final List<FeatureItem> _features = [
    FeatureItem(
      icon: Icons.assignment_outlined,
      title: 'Exam Management',
      description: 'Schedule and organize examination sessions',
    ),
    FeatureItem(
      icon: Icons.event_seat_outlined,
      title: 'Seating Arrangements',
      description: 'Automated hall planning and seat allocation',
    ),
    FeatureItem(
      icon: Icons.people_outline,
      title: 'Faculty Management',
      description: 'Assign invigilators and manage faculty duties',
    ),
    FeatureItem(
      icon: Icons.school_outlined,
      title: 'Student Portal',
      description: 'Access exam schedules and results easily',
    ),
    FeatureItem(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Administration Tools',
      description: 'Specialized access for controllers and superintendents',
    ),
    FeatureItem(
      icon: Icons.lock_outlined,
      title: 'Role-Based Access',
      description: 'Secure permissions for students, faculty, and admins',
    ),
    FeatureItem(
      icon: Icons.dashboard_outlined,
      title: 'Intuitive Dashboards',
      description: 'Custom interfaces for different user roles',
    ),
    FeatureItem(
      icon: Icons.notifications_outlined,
      title: 'Examination Alerts',
      description: 'Important notifications for all stakeholders',
    ),
    FeatureItem(
      icon: Icons.room_outlined,
      title: 'Venue Management',
      description: 'Organize and allocate examination venues',
    ),
    FeatureItem(
      icon: Icons.schedule_outlined,
      title: 'Timetable Generation',
      description: 'Create conflict-free examination schedules',
    ),
    FeatureItem(
      icon: Icons.security_outlined,
      title: 'Secure Authentication',
      description: 'Protected access to examination resources',
    ),
    FeatureItem(
      icon: Icons.support_agent_outlined,
      title: 'Technical Support',
      description: 'Assistance for all system users',
    ),
  ];

  // Focus states
  bool _isIdFieldFocused = false;
  bool _isPasswordFieldFocused = false;
  bool _isHoveringStudent = false;
  bool _isHoveringFaculty = false;
  bool _isHoveringAdminButton = false;

  @override
  void initState() {
    super.initState();

    // Subtle fade-in animation
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    // Subtle slide animation for content
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Feature carousel animation
    _featureCarouselController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _featureOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _featureCarouselController,
        curve: Curves.easeInOut,
      ),
    );

    // Start animations
    _fadeInController.forward();
    _slideController.forward();
    _featureCarouselController.forward();

    // Set up the feature carousel rotation
    _setupFeatureCarousel();
  }

  void _setupFeatureCarousel() {
    // Every 4 seconds, change the feature
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _featureCarouselController.reverse().then((_) {
          setState(() {
            _currentFeatureIndex =
                (_currentFeatureIndex + 1) % _features.length;
          });
          _featureCarouselController.forward();
          _setupFeatureCarousel();
        });
      }
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _fadeInController.dispose();
    _slideController.dispose();
    _featureCarouselController.dispose();
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('An unexpected error occurred'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToAdminLogin() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AdminLoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine if this is a desktop layout
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeInAnimation,
        child: Stack(
          children: [
            // Background with new gradient colors
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0052CC), // Deep blue
                    const Color(0xFF00357A), // Darker blue
                  ],
                ),
              ),
            ),
            // Enhanced pattern overlay
            CustomPaint(
              painter: SubtlePatternPainter(
                color: Colors.white.withOpacity(0.05),
              ),
              size: MediaQuery.of(context).size,
            ),
            // Main content
            if (isDesktop) _buildDesktopLayout() else _buildMobileLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left side - Brand section with feature carousel
        Expanded(
          flex: 5,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 40.0, vertical: 48.0),
            child: SingleChildScrollView(
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo and badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.school,
                            size: 40,
                            color: const Color(0xFF0052CC),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user,
                                size: 16,
                                color: Colors.greenAccent.shade400,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'EDUCATION PORTAL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30), // Reduced spacing
                    // Main title and subtitle
                    const Text(
                      'Office Pal',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12), // Reduced spacing
                    Text(
                      'Examination Management System',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40), // Reduced spacing

                    // Feature carousel
                    Center(child: _buildFeatureCarousel()),

                    // Feature dots indicator
                    const SizedBox(height: 16), // Reduced spacing
                    _buildFeatureDotIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Right side - Login form
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                bottomLeft: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(-5, 0),
                ),
              ],
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48.0),
                child: _buildLoginForm(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCarousel() {
    final currentFeature = _features[_currentFeatureIndex];

    return AnimatedBuilder(
      animation: _featureOpacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _featureOpacityAnimation.value,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Background pattern
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FeatureCardBackgroundPainter(),
                    ),
                  ),
                  // Main content
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 25, horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Remove feature number counter and add more top padding instead
                        const SizedBox(height: 10),

                        // Animated icon with pulse effect
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.95, end: 1.05),
                          duration: const Duration(milliseconds: 2000),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0052CC)
                                          .withOpacity(0.3),
                                      blurRadius: value * 15,
                                      spreadRadius: value * 3,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    currentFeature.icon,
                                    color: Colors.white,
                                    size: 35,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 30),

                        // Title with bottom border
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              currentFeature.title.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                letterSpacing: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: 50,
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.1),
                                    Colors.white,
                                    Colors.white.withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Description - ensure center alignment
                        Text(
                          currentFeature.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            height: 1.5,
                            letterSpacing: 0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 20),

                        // Learn more button
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'LEARN MORE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom accent line
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 4,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF00C6FF),
                            Color(0xFF0072FF),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureDotIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _features.length,
        (index) {
          final isActive = index == _currentFeatureIndex;
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentFeatureIndex = index;
                _featureCarouselController.reset();
                _featureCarouselController.forward();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isActive ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo and badge
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.school,
                  size: 40,
                  color: Color(0xFF0052CC),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Office Pal',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Examination Management System',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user,
                      size: 16,
                      color: Colors.greenAccent.shade400,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'EDUCATION PORTAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Feature showcase
              AnimatedBuilder(
                animation: _featureOpacityAnimation,
                builder: (context, child) {
                  final currentFeature = _features[_currentFeatureIndex];
                  return Opacity(
                    opacity: _featureOpacityAnimation.value,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              currentFeature.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentFeature.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currentFeature.description,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Feature dots indicator (smaller for mobile)
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _features.length,
                    (index) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _currentFeatureIndex
                            ? Colors.white
                            : Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              // Login form
              Container(
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildLoginForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign In',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0052CC),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please login to continue',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),

          // Login mode toggle with improved styling
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringStudent = true),
                    onExit: (_) => setState(() => _isHoveringStudent = false),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _loginMode = LoginMode.student),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _loginMode == LoginMode.student
                              ? const Color(0xFF0052CC)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.school,
                              color: _loginMode == LoginMode.student
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              size: 24,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Student',
                              style: TextStyle(
                                color: _loginMode == LoginMode.student
                                    ? Colors.white
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringFaculty = true),
                    onExit: (_) => setState(() => _isHoveringFaculty = false),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _loginMode = LoginMode.faculty),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _loginMode == LoginMode.faculty
                              ? const Color(0xFF0052CC)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.person,
                              color: _loginMode == LoginMode.faculty
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              size: 24,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Faculty',
                              style: TextStyle(
                                color: _loginMode == LoginMode.faculty
                                    ? Colors.white
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
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
          ),
          const SizedBox(height: 30),

          // ID field with enhanced styling
          Focus(
            onFocusChange: (hasFocus) =>
                setState(() => _isIdFieldFocused = hasFocus),
            child: TextFormField(
              controller: _idController,
              decoration: InputDecoration(
                labelText: _getIdLabel,
                prefixIcon: Icon(
                  Icons.person_outline,
                  color: _isIdFieldFocused
                      ? const Color(0xFF0052CC)
                      : Colors.grey.shade500,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF0052CC),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
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
          const SizedBox(height: 20),

          // Password field with enhanced styling
          Focus(
            onFocusChange: (hasFocus) =>
                setState(() => _isPasswordFieldFocused = hasFocus),
            child: TextFormField(
              controller: _passwordController,
              obscureText: _isObscured,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: _isPasswordFieldFocused
                      ? const Color(0xFF0052CC)
                      : Colors.grey.shade500,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscured ? Icons.visibility : Icons.visibility_off,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () {
                    setState(() => _isObscured = !_isObscured);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF0052CC),
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
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

          // Security note
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loginMode == LoginMode.student
                        ? 'Please Verify Your Password'
                        : 'Please Verify Your Password',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Sign in button with enhanced styling
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0052CC),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 32),

          // Enhanced Admin Login Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00357A),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Administrator Access',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Secure login portal for Controllers and Superintendents',
                  style: TextStyle(
                    color: Color(0xFFCDCDCD),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) =>
                        setState(() => _isHoveringAdminButton = true),
                    onExit: (_) =>
                        setState(() => _isHoveringAdminButton = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: ElevatedButton.icon(
                        onPressed: _navigateToAdminLogin,
                        icon: const Icon(
                          Icons.shield_outlined,
                          size: 18,
                        ),
                        label: const Text('Secure Login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isHoveringAdminButton
                              ? const Color(0xFF0047B3)
                              : const Color(0xFF004099),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Improved pattern painter for subtle background pattern
class SubtlePatternPainter extends CustomPainter {
  final Color color;

  SubtlePatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    final xCount = (size.width / spacing).ceil();
    final yCount = (size.height / spacing).ceil();

    // Draw grid pattern with alternating elements
    for (var i = 0; i < xCount; i++) {
      for (var j = 0; j < yCount; j++) {
        final x = i * spacing;
        final y = j * spacing;

        // Draw small circles or squares in alternating pattern
        if ((i + j) % 2 == 0) {
          // Draw small squares
          final rect = Rect.fromCenter(
            center: Offset(x, y),
            width: 4,
            height: 4,
          );
          canvas.drawRect(rect, paint);
        } else {
          // Draw small circles
          canvas.drawCircle(Offset(x, y), 2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Feature item class
class FeatureItem {
  final IconData icon;
  final String title;
  final String description;

  FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// Custom background painter for feature card
class FeatureCardBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Gradient background
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final Gradient gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0052CC).withOpacity(0.4),
        const Color(0xFF00357A).withOpacity(0.1),
      ],
    );
    final Paint paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // Drawing diagonal lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    for (int i = 0; i < size.width + size.height; i += 40) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(0, i.toDouble()),
        linePaint,
      );
    }

    // Drawing small circles
    final circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.2), 40, circlePaint);
    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.8), 25, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
