import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraScreen extends StatefulWidget {
  final String measurement;
  const CameraScreen({super.key, required this.measurement});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _controller = CameraController(_cameras![0], ResolutionPreset.medium);
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _initialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initalizing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _captureFrame() {
    // ADD MEASUREMENT CALCULATION / pose estimation here
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${widget.measurement} captured!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Measure: ${widget.measurement}')),
      body: Center(
        child: _initialized && _controller != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _captureFrame,
                    child: const Text('Capture'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
