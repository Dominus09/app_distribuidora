import 'package:flutter/material.dart';

class ChoferHomeScreen extends StatelessWidget {
  const ChoferHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chofer')),
      body: const Center(
        child: Text(
          'Entregas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
