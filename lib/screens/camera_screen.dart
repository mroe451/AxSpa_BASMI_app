import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:html' as html;
import '../services/pose_service.dart';
import 'dart:js_util' as js_util;

class CameraScreen extends StatefulWidget {
  final String measurement;
  const CameraScreen({super.key, required this.measurement});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  List<dynamic>? _keypoints;
  bool _initialized = false;
  int? _videoW;
  int? _videoH;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // await Future.delayed(Duration(milliseconds: 500));

    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _controller = CameraController(_cameras![0], ResolutionPreset.medium);
        await _controller!.initialize();
        await initPose();
        _startPoseLoop();
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

  void _startPoseLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 300));

      final video = html.document.querySelector('video') as html.VideoElement;
      if (video == null) continue;

      final vw = video.videoWidth;
      final vh = video.videoHeight;
      if (vw == 0 || vh == 0) continue;

      final keypoints = await detectPose(video);
      if (keypoints == null) continue;
      // print(keypoints);
      // for (var kp in keypoints) {
      //   final name = js_util.getProperty(kp, 'name');
      //   final x = js_util.getProperty(kp, 'x');
      //   final y = js_util.getProperty(kp, 'y');
      //
      //   print("$name x:$x y:$y");
      // }
      // print("----");
      setState(() {
        _videoW = vw;
        _videoH = vh;
        _keypoints = keypoints as List<dynamic>;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Measure: ${widget.measurement}')),
      body: Center(
        child: _initialized && _controller != null
            ? Stack(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),

                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: GuideOverlayPainter(
                          keypoints: _keypoints,
                          videoW: _videoW,
                          videoH: _videoH, //issue here?
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Text(
                      "Stand inside the box and press Capture",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: _captureFrame,
                        child: const Text("Capture"),
                      ),
                    ),
                  ),

                  // const SizedBox(height: 16),
                  // ElevatedButton(
                  //   onPressed: _captureFrame,
                  //   child: const Text('Capture'),
                  // ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class GuideOverlayPainter extends CustomPainter {
  final List<dynamic>? keypoints;
  final int? videoW;
  final int? videoH;

  GuideOverlayPainter({this.keypoints, this.videoW, this.videoH});

  @override
  void paint(Canvas canvas, Size size) {
    // Box frame
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.6,
      height: size.height * 0.75,
    );

    canvas.drawRect(rect, paint);

    if (keypoints == null || videoW == null || videoH == null) return;
    if (videoW == 0 || videoH == 0) return;

    // final dotPaint = Paint()..style = PaintingStyle.fill;

    final vw = videoW!.toDouble();
    final vh = videoH!.toDouble();

    final cw = size.width;
    final ch = size.height;

    final videoAspect = vw / vh;
    final canvasAspect = cw / ch;

    double scale, offsetX, offsetY;

    if (canvasAspect > videoAspect) {
      final displayedW = ch * videoAspect;
      scale = displayedW / vw;
      offsetX = (cw - displayedW) / 2;
      offsetY = 0;
    } else {
      final displayedH = cw / videoAspect;
      scale = displayedH / vh;
      offsetX = 0;
      offsetY = (ch - displayedH) / 2;
    }

    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (final kp in keypoints!) {
      final score = (js_util.getProperty(kp, 'score') as num).toDouble();
      if (score < 0.4) continue;

      final x = (js_util.getProperty(kp, 'x') as num).toDouble();
      final y = (js_util.getProperty(kp, 'y') as num).toDouble();

      final dx = offsetX + x * scale;
      final dy = offsetY + y * scale;

      final mirroredDx = size.width - dx;

      canvas.drawCircle(Offset(mirroredDx, dy), 5, dotPaint);
    }

    //
    // // canvas.drawLine(
    // //   Offset(0, size.height / 2),
    // //   Offset(size.width, size.height / 2),
    // //   paint,
    // // );
    //
    // if (keypoints != null) {

    //
    //   for (final kp in keypoints!) {
    //     final x = (js_util.getProperty(kp, 'x') as num).toDouble();
    //     final y = (js_util.getProperty(kp, 'y') as num).toDouble();
    //     final score = (js_util.getProperty(kp, 'score') as num).toDouble();
    //
    //     if (score < 0.4) continue;
    //
    //     //toggle if points are mirrored
    //     final drawX = size.width - x;
    //     // final drawX = x;
    //
    //     canvas.drawCircle(Offset(drawX, y), 6, dotPaint);
    //   }
    // }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
  // {  return oldDelegate.keypoints != keypoints ||
  //       oldDelegate.videoW != videoW ||
  //       oldDelegate.videoH != videoH;
  // }
}
