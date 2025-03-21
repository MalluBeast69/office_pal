import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/features/superintendent/presentation/pages/superintendent_dashboard_page.dart';
import 'package:office_pal/features/controller/presentation/pages/controller_dashboard_page.dart';

enum AdminLoginMode { superintendent, controller }

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isObscured = true;
  AdminLoginMode _loginMode = AdminLoginMode.superintendent;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Animation controller
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  // Focus states
  bool _isEmailFieldFocused = false;
  bool _isPasswordFieldFocused = false;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  String get _getHintText {
    return _loginMode == AdminLoginMode.superintendent
        ? 'superintendent@examination.com'
        : 'controller@examination.com';
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Login successful!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

        // Navigate to the appropriate dashboard based on login mode
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  _loginMode == AdminLoginMode.superintendent
                  ? const SuperintendentDashboardPage()
                  : const ControllerDashboardPage(),
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
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeInAnimation,
        child: Stack(
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A2C42),
                    const Color(0xFF121E2E),
                  ],
                ),
              ),
            ),
            // Background pattern
            CustomPaint(
              painter: AdminPatternPainter(
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
        // Left side - Security image and info
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo and secure badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.school,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
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
                            'SECURE PORTAL',
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
                const SizedBox(height: 60),
                const Text(
                  'Admin Portal',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Secure access for examination officials',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 40),
                // Security features
                _buildSecurityFeature(
                  icon: Icons.verified_user_outlined,
                  title: 'Verified Access',
                  description: 'Strict authentication protocols',
                ),
                const SizedBox(height: 20),
                _buildSecurityFeature(
                  icon: Icons.lock_outlined,
                  title: 'Encrypted Connection',
                  description: 'End-to-end data protection',
                ),
                const SizedBox(height: 20),
                _buildSecurityFeature(
                  icon: Icons.shield_outlined,
                  title: 'Role-Based Access',
                  description: 'Controlled permissions system',
                ),
                const SizedBox(height: 60),
                // Admin shield icon
                Icon(
                  Icons.admin_panel_settings,
                  size: 80,
                  color: Colors.white.withOpacity(0.15),
                ),
              ],
            ),
          ),
        ),
        // Right side - Login form
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                bottomLeft: Radius.circular(30),
              ),
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

  Widget _buildSecurityFeature({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo and secure badge
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                size: 50,
                color: Color(0xFF1A2C42),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Admin Portal',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Secure access for examination officials',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    'SECURE PORTAL',
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
            'Administrator Sign In',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A2C42),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your credentials to access the admin portal',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
                ),
                const SizedBox(height: 32),

          // Administrator Type Selector
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
                  child: InkWell(
                    onTap: () => setState(
                        () => _loginMode = AdminLoginMode.superintendent),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _loginMode == AdminLoginMode.superintendent
                            ? const Color(0xFF1A2C42)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            color: _loginMode == AdminLoginMode.superintendent
                                ? Colors.white
                                : Colors.grey.shade500,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Superintendent',
                            style: TextStyle(
                              color: _loginMode == AdminLoginMode.superintendent
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
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _loginMode = AdminLoginMode.controller),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _loginMode == AdminLoginMode.controller
                            ? const Color(0xFF1A2C42)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.manage_accounts,
                            color: _loginMode == AdminLoginMode.controller
                                ? Colors.white
                                : Colors.grey.shade500,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Controller',
                            style: TextStyle(
                              color: _loginMode == AdminLoginMode.controller
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
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Email field
          Focus(
            onFocusChange: (hasFocus) =>
                setState(() => _isEmailFieldFocused = hasFocus),
            child: TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                hintText: _getHintText,
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: _isEmailFieldFocused
                      ? const Color(0xFF1A2C42)
                      : Colors.grey.shade500,
                ),
                    border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF1A2C42),
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
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
          ),
          const SizedBox(height: 20),

          // Password field
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
                      ? const Color(0xFF1A2C42)
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
                    color: Color(0xFF1A2C42),
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

          const SizedBox(height: 12),

          // Security recommendation
          Container(
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
                    'Access from secure network. Logout when not in use.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Sign in button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2C42),
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
                        const Icon(Icons.shield_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Secure Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
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
}

// Custom pattern painter for the admin background
class AdminPatternPainter extends CustomPainter {
  final Color color;

  AdminPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    final xCount = (size.width / spacing).ceil();
    final yCount = (size.height / spacing).ceil();

    // Draw grid pattern
    for (var i = 0; i < xCount; i++) {
      for (var j = 0; j < yCount; j++) {
        final x = i * spacing;
        final y = j * spacing;

        // Draw small squares
        if ((i + j) % 2 == 0) {
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
