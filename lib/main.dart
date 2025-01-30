import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/superintendent/presentation/pages/superintendent_dashboard_page.dart';
import 'features/controller/presentation/pages/controller_dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fnxirlpiqciezifongxb.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZueGlybHBpcWNpZXppZm9uZ3hiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYzNjIxMzgsImV4cCI6MjA1MTkzODEzOH0.qbqwZJr9ufNbs3mjQHFuJMNlef-mUwBNoCaoeuHDGhM',
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Simulate some initialization time
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Office Pal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Define named routes
      routes: {
        '/': (context) =>
            _isLoading ? const LoadingScreen() : const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/superintendent': (context) => const SuperintendentDashboardPage(),
        '/controller': (context) => const ControllerDashboardPage(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Debug print to track auth state
        print('Auth state changed: ${snapshot.data?.session?.user.email}');

        if (!snapshot.hasData || snapshot.data?.session == null) {
          return const LoginPage();
        }

        final userEmail =
            snapshot.data?.session?.user.email?.toLowerCase() ?? '';
        print('User email: $userEmail');

        // More specific email checks
        if (userEmail.isEmpty) {
          return const LoginPage();
        }

        if (userEmail.contains('superintendent')) {
          return const SuperintendentDashboardPage();
        } else if (userEmail.toLowerCase().contains('controller')) {
          print('Navigating to Controller Dashboard');
          return const ControllerDashboardPage();
        }

        print('No role match found, returning to login');
        return const LoginPage();
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
              const Text(
                'Office Pal',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// superintendent@examination.com