import 'package:flutter/material.dart';

class BodegaHomeScreen extends StatelessWidget {
  const BodegaHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bodega')),
      body: const Center(
        child: Text(
          'Picking',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
