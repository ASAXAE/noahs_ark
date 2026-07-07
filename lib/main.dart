import 'package:flutter/material.dart';
import 'screens/home/home_page.dart';

void main() {
  runApp(const NoahApp());
}

class NoahApp extends StatelessWidget {
  const NoahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Noah's Ark",
      home: const HomePage(),
    );
  }
}
