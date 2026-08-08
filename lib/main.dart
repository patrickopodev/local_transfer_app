import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const LocalTransferApp());
}

class LocalTransferApp extends StatelessWidget {
  const LocalTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Transfer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const HomeScreen(),
    );
  }
}