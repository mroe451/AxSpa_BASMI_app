import 'package:flutter/material.dart';
import 'camera_screen.dart';

class BasmiMenu extends StatelessWidget {
  const BasmiMenu({super.key});

  final List<String> measurements = const [
    'Cervial Rotation',
    'Lateral Flexion',
    'Lumbar Flexion',
    'Intermalleolar Distance',
    'Tragus-to-Wall Distance',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Measurement')),
      body: ListView.builder(
        itemCount: measurements.length,
        itemBuilder: (context, index) {
          final measurement = measurements[index];
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              child: Text(measurement),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CameraScreen(measurement: measurement),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
