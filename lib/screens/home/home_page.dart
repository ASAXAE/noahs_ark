import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("诺亚方舟"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "🌱 今日思考",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            const Text("今天有什么想记录的吗？", style: TextStyle(fontSize: 18)),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text("开始记录"),
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "最近记录",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Card(
              child: ListTile(
                leading: const Icon(Icons.book),
                title: const Text("今天学习Flutter"),
                subtitle: const Text("2026/07/07"),
              ),
            ),

            Card(
              child: ListTile(
                leading: const Icon(Icons.book),
                title: const Text("今天开始诺亚方舟"),
                subtitle: const Text("2026/07/06"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
