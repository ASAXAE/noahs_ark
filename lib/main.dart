import 'package:flutter/material.dart';

void main() {
  runApp(const NoahApp());
}

class NoahApp extends StatelessWidget {
  const NoahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Noah's Ark",
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text("诺亚方舟")),
        body: const Center(
          child: Text("欢迎来到诺亚方舟", style: TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}
