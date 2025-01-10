import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:office_pal/core/constants.dart';
import 'package:office_pal/features/auth/presentation/pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Constants.supabaseUrl,
    anonKey: Constants.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Office Pal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
      onGenerateRoute: (settings) {
        // Define your routes here
        switch (settings.name) {
          case '/':
          case '/login':
            return MaterialPageRoute(
              builder: (context) => const LoginPage(),
            );
          default:
            // If the route is not found, navigate to login page
            return MaterialPageRoute(
              builder: (context) => const LoginPage(),
            );
        }
      },
    );
  }
}
