import 'package:flutter/material.dart';
import 'eligibility_page.dart'; // Will be created

void main() => runApp(const AllAroundApp());

class AllAroundApp extends StatelessWidget {
  const AllAroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'All-Around Eligibility',
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.dark,
            primary: Colors.blueAccent,
            onPrimary: Colors.white,
            secondary: Colors.lightBlueAccent,
            onSecondary: Colors.white,
            surface: Colors.blueGrey[900]!,
            onSurface: Colors.white,
          ),
          textTheme: const TextTheme(
            titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            bodyMedium: TextStyle(color: Colors.white70),
            titleSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), // Added for consistency
          ),
        ),
        home: const EligibilityPage(),
        debugShowCheckedModeBanner: false,
      );
}