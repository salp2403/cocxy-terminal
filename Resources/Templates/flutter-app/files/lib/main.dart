import 'package:flutter/material.dart';

void main() {
  runApp(const CocxyApp());
}

class CocxyApp extends StatelessWidget {
  const CocxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('{{app_title}}')),
      ),
    );
  }
}
