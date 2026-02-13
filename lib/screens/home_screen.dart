import 'package:flutter/material.dart';
import 'basmi_menu.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AxSpa BASMI App')),
      body: Center(
        child: ElevatedButton(
          child: const Text('Start BASMI Assessment'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BasmiMenu()),
            );
          },
        ),
      ),
    );
  }
}
