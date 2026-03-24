import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:html' as html;
import '../services/pose_service.dart';
import 'dart:js_util' as js_util;
import 'dart:math';

class CameraScreen extends StatefulWidget {
  final String measurement;
  final void Function(String measurement, String result)? onMeasurementSaved;

  const CameraScreen({
    super.key,
    required this.measurement,
    this.onMeasurementSaved,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  List<dynamic>? _keypoints;
  List<dynamic>? _capturedStart;
  List<dynamic>? _capturedEnd;
  bool _initialized = false;
  bool _guidanceOn = true;
  int? _videoW;
  int? _videoH;
  String _stage = "positioning";
  String _resultText = "";

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
    // // ADD MEASUREMENT CALCULATION / pose estimation here
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text('${widget.measurement} captured!')));

    if (_keypoints == null) return;

    final snapshot = List<dynamic>.from(_keypoints!);

    if (_stage == "positioning") {
      _capturedStart = snapshot;

      setState(() {
        _stage = "capturedStart";
        _resultText = "Start captured. Move into position.";
      });
    } else if (_stage == "capturedStart") {
      _capturedEnd = snapshot;

      _calculateMeasurement();

      setState(() {
        _stage = "result";
      });
    }
  }

  void _reset() {
    setState(() {
      _capturedStart = null;
      _capturedEnd = null;
      _stage = "positioning";
      _resultText = "";
    });
  }

  void _calculateMeasurement() {
    if (widget.measurement == "Intermalleolar Distance") {
      _calculateIntermalleolar();
    } else if (widget.measurement == "Lateral Flexion") {
      _calculateSideFlexion();
    } else if (widget.measurement == "Cervical Rotation") {
      _calculateCervicalRotation();
    }
  }

  void _calculateIntermalleolar() {
    if (_capturedStart == null) return;

    final leftAnkle = getKeypoint(_capturedStart!, 'left_ankle');
    final rightAnkle = getKeypoint(_capturedStart!, 'right_ankle');

    if (leftAnkle == null || rightAnkle == null) {
      _setAndSaveResult("Ankles not detected properly");
      return;
    }

    final distPx = distance(leftAnkle, rightAnkle);

    final approxCm = distPx * 0.1;

    _setAndSaveResult("Distance: ${approxCm.toStringAsFixed(1)} cm");
  }

  void _calculateSideFlexion() {
    if (_capturedStart == null || _capturedEnd == null) return;

    final startWrist = getKeypoint(_capturedStart!, 'left_wrist');
    final startHip = getKeypoint(_capturedStart!, 'left_hip');

    final endWrist = getKeypoint(_capturedEnd!, 'left_wrist');
    final endHip = getKeypoint(_capturedEnd!, 'left_hip');

    if (startWrist == null ||
        startHip == null ||
        endWrist == null ||
        endHip == null) {
      _setAndSaveResult("Could not detect side flexion landmarks");
      return;
    }

    final startOffset = getY(startWrist) - getY(startHip);
    final endOffset = getY(endWrist) - getY(endHip);

    final deltaPx = endOffset - startOffset;
    final approxCm = deltaPx.abs() * 0.1;

    _setAndSaveResult("Side flexion: ${approxCm.toStringAsFixed(1)} cm");
  }

  void _calculateCervicalRotation() {
    if (_capturedStart == null || _capturedEnd == null) return;

    final startNose = getKeypoint(_capturedStart!, 'nose');
    final startLeftShoulder = getKeypoint(_capturedStart!, 'left_shoulder');
    final startRightShoulder = getKeypoint(_capturedStart!, 'right_shoulder');

    final endNose = getKeypoint(_capturedEnd!, 'nose');
    final endLeftShoulder = getKeypoint(_capturedStart!, 'left_shoulder');
    final endRightShoulder = getKeypoint(_capturedStart!, 'right_shoulder');

    if (startNose == null ||
        startLeftShoulder == null ||
        startRightShoulder == null ||
        endNose == null ||
        endLeftShoulder == null ||
        endRightShoulder == null) {
      _setAndSaveResult("Could not detect cervical rotation landmarks");
      return;
    }

    final startMidX =
        (getX(startLeftShoulder) + getX(startRightShoulder)) / 2.0;
    final startMidY =
        (getY(startLeftShoulder) + getY(startRightShoulder)) / 2.0;

    final endMidX = (getX(endLeftShoulder) + getX(endRightShoulder)) / 2.0;
    final endMidY = (getY(endLeftShoulder) + getY(endRightShoulder)) / 2.0;

    final startAngle = atan2(
      getY(startNose) - startMidY,
      getX(startNose) - startMidX,
    );
    final endAngle = atan2(getY(endNose) - endMidY, getX(endNose) - endMidX);

    final deltaRad = endAngle - startAngle;
    final deltaDeg = (deltaRad * 180 / pi).abs();

    _setAndSaveResult(
      "Cervical rotation: ${deltaDeg.toStringAsFixed(1)} degrees",
    );
  }

  void _setAndSaveResult(String result) {
    _resultText = result;
    widget.onMeasurementSaved?.call(widget.measurement, result);
  }

  String _instructionText() {
    if (widget.measurement == "Intermalleolar Distance") {
      return _stage == "positioning"
          ? "Stand facing the camera and capture your starting position"
          : "Move your feet apart and capture again";
    } else if (widget.measurement == "Lateral Flexion") {
      return _stage == "positioning"
          ? "Stand upright and capture your neutral posture"
          : "Bend sideways and capture the final position";
    } else if (widget.measurement == "Cervical Rotation") {
      return _stage == "positioning"
          ? "Face forward and capture your neutral head position"
          : "Rotate your head and capture the final position";
    }
    return "Stand inside the box and press capture";
  }

  void _startPoseLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 300));

      // final video = html.document.querySelector('video') as html.VideoElement;
      // if (video == null) continue;

      final videoE1 = html.document.querySelector('video');
      if (videoE1 is! html.VideoElement) continue;

      final video = videoE1;

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

  GuidanceState _guidanceState() {
    if (_keypoints == null) {
      return GuidanceState(isReady: false, lines: []);
    }

    if (widget.measurement == 'Cervical Rotation') {
      return _guidanceForCervical();
    } else if (widget.measurement == 'Lateral Flexion') {
      return _guidanceForLateralFlexion();
    } else if (widget.measurement == 'Intermalleolar Distance') {
      return _guidanceForIntermalleolar();
    }

    return GuidanceState(isReady: false, lines: []);
  }

  GuidanceState _guidanceForCervical() {
    final leftShoulder = getKeypoint(_keypoints!, 'left_shoulder');
    final rightShoulder = getKeypoint(_keypoints!, 'right_shoulder');
    final nose = getKeypoint(_keypoints!, 'nose');

    if (!hasGoodScore(leftShoulder) ||
        !hasGoodScore(rightShoulder) ||
        !hasGoodScore(nose)) {
      return GuidanceState(isReady: false, lines: []);
    }

    final shoulderLevel = absDiff(getY(leftShoulder), getY(rightShoulder)) < 20;

    final shoulderMidX = (getX(leftShoulder) + getX(rightShoulder)) / 2.0;
    final noseCentered = absDiff(getX(nose), shoulderMidX) < 35;

    final isReady = shoulderLevel && noseCentered;

    return GuidanceState(
      isReady: isReady,
      lines: [
        GuideLine(
          startName: 'left_shoulder',
          endName: 'right_shoulder',
          color: shoulderLevel ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'nose',
          endName: 'left_shoulder',
          color: noseCentered ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'nose',
          endName: 'right_shoulder',
          color: noseCentered ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  GuidanceState _guidanceForLateralFlexion() {
    final leftShoulder = getKeypoint(_keypoints!, 'left_shoulder');
    final rightShoulder = getKeypoint(_keypoints!, 'right_shoulder');
    final leftHip = getKeypoint(_keypoints!, 'left_hip');
    final rightHip = getKeypoint(_keypoints!, 'right_hip');
    final leftElbow = getKeypoint(_keypoints!, 'left_elbow');
    final rightElbow = getKeypoint(_keypoints!, 'right_elbow');
    final leftWrist = getKeypoint(_keypoints!, 'left_wrist');
    final rightWrist = getKeypoint(_keypoints!, 'right_wrist');
    final leftKnee = getKeypoint(_keypoints!, 'left_knee');
    final rightKnee = getKeypoint(_keypoints!, 'right_knee');
    final leftAnkle = getKeypoint(_keypoints!, 'left_ankle');
    final rightAnkle = getKeypoint(_keypoints!, 'right_ankle');

    final required = [
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
      leftElbow,
      rightElbow,
      leftWrist,
      rightWrist,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
    ];

    if (required.any((kp) => !hasGoodScore(kp))) {
      return GuidanceState(isReady: false, lines: []);
    }

    final shouldersLevel =
        absDiff(getY(leftShoulder), getY(rightShoulder)) < 20;
    final hipsLevel = absDiff(getY(leftHip), getY(rightHip)) < 20;

    final leftKneeAngle = angleBetweenPoints(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = angleBetweenPoints(rightHip, rightKnee, rightAnkle);
    final kneesStraight = leftKneeAngle > 170 && rightKneeAngle > 170;

    final leftElbowAngle = angleBetweenPoints(
      leftShoulder,
      leftElbow,
      leftWrist,
    );
    final rightElbowAngle = angleBetweenPoints(
      rightShoulder,
      rightElbow,
      rightWrist,
    );
    final armsStraight = leftElbowAngle > 155 && rightElbowAngle > 155;

    final footDistance = distance(leftAnkle, rightAnkle);
    final hipWidth = distance(leftHip, rightHip);
    final feetApartEnough = hipWidth > 0 && footDistance > hipWidth * 1.2;

    final isReady =
        shouldersLevel &&
        hipsLevel &&
        kneesStraight &&
        armsStraight &&
        feetApartEnough;

    return GuidanceState(
      isReady: isReady,
      lines: [
        GuideLine(
          startName: 'left_shoulder',
          endName: 'right_shoulder',
          color: shouldersLevel ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_hip',
          endName: 'right_hip',
          color: hipsLevel ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_hip',
          endName: 'left_knee',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_knee',
          endName: 'left_ankle',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_hip',
          endName: 'right_knee',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_knee',
          endName: 'right_ankle',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_shoulder',
          endName: 'left_elbow',
          color: armsStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_elbow',
          endName: 'left_wrist',
          color: armsStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_shoulder',
          endName: 'right_elbow',
          color: armsStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_elbow',
          endName: 'right_wrist',
          color: armsStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_ankle',
          endName: 'right_ankle',
          color: feetApartEnough ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  GuidanceState _guidanceForIntermalleolar() {
    final leftHip = getKeypoint(_keypoints!, 'left_hip');
    final rightHip = getKeypoint(_keypoints!, 'right_hip');
    final leftKnee = getKeypoint(_keypoints!, 'left_knee');
    final rightKnee = getKeypoint(_keypoints!, 'right_knee');
    final leftAnkle = getKeypoint(_keypoints!, 'left_ankle');
    final rightAnkle = getKeypoint(_keypoints!, 'right_ankle');

    final required = [
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
    ];

    if (required.any((kp) => !hasGoodScore(kp))) {
      return GuidanceState(isReady: false, lines: []);
    }

    final leftKneeAngle = angleBetweenPoints(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = angleBetweenPoints(rightHip, rightKnee, rightAnkle);
    final kneesStraight = leftKneeAngle > 170 && rightKneeAngle > 170;

    final hipsLevel = absDiff(getY(leftHip), getY(rightHip)) < 20;

    final isReady = kneesStraight && hipsLevel;

    return GuidanceState(
      isReady: isReady,
      lines: [
        GuideLine(
          startName: 'left_hip',
          endName: 'left_knee',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_knee',
          endName: 'left_ankle',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_hip',
          endName: 'right_knee',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'right_knee',
          endName: 'right_ankle',
          color: kneesStraight ? Colors.green : Colors.red,
        ),
        GuideLine(
          startName: 'left_hip',
          endName: 'right_hip',
          color: hipsLevel ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final guidanceState = _guidanceState();
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

                  Positioned(
                    top: 20,
                    right: 20,
                    child: Row(
                      children: [
                        const Text(
                          "Guidance",
                          style: TextStyle(color: Colors.white),
                        ),
                        Switch(
                          value: _guidanceOn,
                          onChanged: (val) {
                            setState(() {
                              _guidanceOn = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: GuideOverlayPainter(
                          keypoints: _keypoints,
                          videoW: _videoW,
                          videoH: _videoH, //issue here?
                          guidanceOn: _guidanceOn,
                          isReady: guidanceState.isReady,
                          guideLines: guidanceState.lines,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Text(
                      _instructionText(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 140,
                    left: 0,
                    right: 0,
                    child: Text(
                      _resultText,
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
                        child: Text(
                          _stage == "positioning"
                              ? "Capture Start"
                              : "Capture End",
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: _reset,
                        child: const Text("Reset"),
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
  final bool guidanceOn;
  final bool isReady;
  final List<GuideLine> guideLines;

  GuideOverlayPainter({
    this.keypoints,
    this.videoW,
    this.videoH,
    required this.guidanceOn,
    required this.isReady,
    required this.guideLines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Box frame
    if (!guidanceOn) return;

    final paint = Paint()
      // ..color = Colors.white.withOpacity(0.7)
      ..color = isReady ? Colors.green : Colors.red
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

      // canvas.drawCircle(Offset(mirroredDx, dy), 5, dotPaint);
    }

    Offset? mapKeypointToCanvas(String name) {
      if (keypoints == null) return null;

      final kp = getKeypoint(keypoints!, name);
      if (kp == null || !hasGoodScore(kp)) return null;

      final x = getX(kp);
      final y = getY(kp);

      final dx = offsetX + x * scale;
      final dy = offsetY + y * scale;
      final mirroredDx = size.width - dx;

      return Offset(mirroredDx, dy);
    }

    for (final line in guideLines) {
      final p1 = mapKeypointToCanvas(line.startName);
      final p2 = mapKeypointToCanvas(line.endName);

      if (p1 == null || p2 == null) continue;

      final linePaint = Paint()
        ..color = line.color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

      canvas.drawLine(p1, p2, linePaint);
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

dynamic getKeypoint(List<dynamic> keypoints, String name) {
  return keypoints.firstWhere(
    (kp) => js_util.getProperty(kp, 'name') == name,
    orElse: () => null,
  );
}

double getX(dynamic kp) => (js_util.getProperty(kp, 'x') as num).toDouble();

double getY(dynamic kp) => (js_util.getProperty(kp, 'y') as num).toDouble();

double distance(dynamic p1, dynamic p2) {
  final dx = getX(p1) - getX(p2);
  final dy = getY(p1) - getY(p2);
  return sqrt(dx * dx + dy * dy);
}

class GuideLine {
  final String startName;
  final String endName;
  final Color color;

  GuideLine({
    required this.startName,
    required this.endName,
    required this.color,
  });
}

class GuidanceState {
  final bool isReady;
  final List<GuideLine> lines;

  GuidanceState({required this.isReady, required this.lines});
}

double getScore(dynamic kp) =>
    (js_util.getProperty(kp, 'score') as num).toDouble();

bool hasGoodScore(dynamic kp, [double threshold = 0.4]) {
  if (kp == null) return false;
  return getScore(kp) >= threshold;
}

double angleBetweenPoints(dynamic a, dynamic b, dynamic c) {
  final abX = getX(a) - getX(b);
  final abY = getY(a) - getY(b);
  final cbX = getX(c) - getX(b);
  final cbY = getY(c) - getY(b);

  final dot = abX * cbX + abY * cbY;
  final mag1 = sqrt(abX * abX + abY * abY);
  final mag2 = sqrt(cbX * cbX + cbY * cbY);

  if (mag1 == 0 || mag2 == 0) return 0;

  final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
  return acos(cosTheta) * 180 / pi;
}

double absDiff(double a, double b) => (a - b).abs();
