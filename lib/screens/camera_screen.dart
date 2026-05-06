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
  String _stage = "cameraSetup";
  String _resultText = "";
  bool _autoMode = true;
  int? _countdownValue;
  DateTime? _readySince;
  DateTime? _movementSince;
  bool _countdownRunning = false;
  bool _isCalibrating = false;
  bool _awaitingAnkleWidthAfterCalib = false;
  Offset? _calibPoint1;
  Offset? _calibPoint2;
  double? _cmPerPixel;
  final GlobalKey _previewKey = GlobalKey();
  double? _ankleWidthCm;
  static const primaryColor = Color(0xFF4FF6F5);
  static const backgroundColor = Color(0xFFF8FAFC);

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

  /// captures current keypoints from camera for calculation
  void _captureFrame() {
    if (_keypoints == null) {
      return;
    }

    final snapshot = List<dynamic>.from(_keypoints!);

    if (widget.measurement == "Intermalleolar Distance") {
      _capturedStart = snapshot;
      _calculateIntermalleolar();

      setState(() {
        _stage = "result";
      });
      return;
    }

    if (_stage == "positioning") {
      _capturedStart = snapshot;

      setState(() {
        _stage = "capturedStart";
        _resultText = "";
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
      _stage = "cameraSetup";
      _resultText = "";
      _countdownValue = null;
      _isCalibrating = false;
      _calibPoint1 = null;
      _calibPoint2 = null;
      _awaitingAnkleWidthAfterCalib = false;
    });
    _readySince = null;
    _movementSince = null;
    _countdownRunning = false;
  }

  /// handles which measurement to calculate depedning on which basmi measurement selected
  void _calculateMeasurement() {
    if (widget.measurement == "Intermalleolar Distance") {
      _calculateIntermalleolar();
    } else if (widget.measurement == "Lumbar Side Flexion") {
      _calculateSideFlexion();
    } else if (widget.measurement == "Cervical Rotation") {
      _calculateCervicalRotation();
    }
  }

  /// calculates intermalleolar distance
  void _calculateIntermalleolar() {
    if (_capturedStart == null) {
      return;
    }

    final leftAnkle = getKeypoint(_capturedStart!, 'left_ankle');
    final rightAnkle = getKeypoint(_capturedStart!, 'right_ankle');

    if (leftAnkle == null || rightAnkle == null) {
      _setAndSaveResult("Ankles not detected properly");
      return;
    }

    final distPx = distance(leftAnkle, rightAnkle);
    final approxCm = _pxToCm(distPx);

    if (approxCm == null) {
      _setAndSaveResult("Calibration required");
      return;
    }

    double correctedCm = approxCm;
    if (_ankleWidthCm != null && _ankleWidthCm! > 0) {
      correctedCm = (approxCm - (_ankleWidthCm! * 1.1)).clamp(
        0.0,
        double.infinity,
      );
    }

    if (_ankleWidthCm != null) {
      _setAndSaveResult("${correctedCm.toStringAsFixed(1)} cm");
    } else {
      _setAndSaveResult("Distance: ${approxCm.toStringAsFixed(1)} cm");
    }
  }

  /// side flexion calculation
  void _calculateSideFlexion() {
    if (_capturedStart == null || _capturedEnd == null) {
      return;
    }

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
    final approxCm = _pxToCm(deltaPx.abs());

    if (approxCm == null) {
      _setAndSaveResult("Calibration required");
      return;
    }
    _setAndSaveResult("${approxCm.toStringAsFixed(1)} cm");
  }

  /// Cervical rotation calculation
  void _calculateCervicalRotation() {
    if (_capturedStart == null || _capturedEnd == null) {
      return;
    }

    final startNose = getKeypoint(_capturedStart!, 'nose');
    final startLeftShoulder = getKeypoint(_capturedStart!, 'left_shoulder');
    final startRightShoulder = getKeypoint(_capturedStart!, 'right_shoulder');

    final endNose = getKeypoint(_capturedEnd!, 'nose');
    final endLeftShoulder = getKeypoint(_capturedEnd!, 'left_shoulder');
    final endRightShoulder = getKeypoint(_capturedEnd!, 'right_shoulder');

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

    _setAndSaveResult("${deltaDeg.toStringAsFixed(1)} degrees");
  }

  ///updates displayed measurement result and for basmi menu
  void _setAndSaveResult(String result) {
    setState(() {
      _resultText = result;
    });
    widget.onMeasurementSaved?.call(widget.measurement, result);
  }

  /// changes top bar display to show what stage measurement is to user
  String _stageTitle() {
    if (_isCalibrating) return "Stage: Calibration";

    if (_countdownValue != null) return "Stage: Capturing";

    if (_stage == "cameraSetup") return "Stage: Camera Setup";
    if (_stage == "positioning") return "Stage: Start Position";
    if (_stage == "capturedStart") return "Stage: Movement";
    if (_stage == "result") return "Stage: Complete";

    return "Measurement";
  }

  /// handles what instructions to display on screen depending on progress through measurment so system state
  String _displayMessage() {
    if (_stage == "cameraSetup") {
      if (widget.measurement == "Cervical Rotation") {
        return "Place the camera on a table directly in front of you so your head and shoulders are clearly visible. When ready, click Camera Set Up Complete";
      }

      if ((widget.measurement == "Lumbar Side Flexion" ||
          widget.measurement == "Intermalleolar Distance")) {
        return "Place the camera low down 2-3 meters away so that your feet to shoulders are visible during measurement. Place the Calibration Object next to where you will stand. When ready, click Camera Set Up Complete to move onto Calibration";
      }

      // if (_cmPerPixel == null && widget.measurement != "Cervical Rotation") {
      //   return "Place the calibration object in view, then click Start Calibration";
      // }

      // if (widget.measurement == "Intermalleolar Distance" &&
      //     _ankleWidthCm == null) {
      //   return "Enter your ankle width using the button on the left, then continue";
      // }

      // return widget.measurement == "Cervical Rotation"
      //     ? "Position the camera so your upper body is clear and you can face straight forward"
      //     : "Position the camera so your full body and calibration object are clearly visible, then press Camera Set Up Complete";
      return "Begin camera setup";
    }

    if (_cmPerPixel == null &&
        widget.measurement != "Cervical Rotation" &&
        !_isCalibrating) {
      return "Calibration required: Click Calibration on the left to begin";
    }

    if (_isCalibrating) {
      if (_awaitingAnkleWidthAfterCalib) {
        return "Enter your ankle width to finish setup";
      }
      if (_calibPoint1 == null) {
        return "Click the first point on the Calibration Object";
      }
      if (_calibPoint2 == null) {
        return "First point selected. Click the second point on the Calibration Object. Do not move the camera after this";
      }
      return "Enter the real distance between these two points";
    }

    // if (_ankleWidthCm == null &&
    //     widget.measurement == "Intermalleolar Distance") {
    //   return "Please click Ankle Width on the left and enter the width of your ankle";
    // }

    if (_countdownValue != null) {
      return "Hold still... preparing to capture";
    }

    if (_stage == "result" && _resultText.isNotEmpty) {
      return "Measurement Complete: ${_resultText}. You may now return to the previous page.";
    }

    if (widget.measurement == "Intermalleolar Distance") {
      return "In line with Calibration Object, Stand with feet as far apart as comfortable and hold still when all lines are green for capture";
    }

    if (widget.measurement == "Lumbar Side Flexion") {
      return _stage == "positioning"
          ? "In line with Calibration Object, stand upright and hold still when all lines are green for capture"
          : "Reach to the floor by side flexing to the left, then hold still for capture";
    }

    if (widget.measurement == "Cervical Rotation") {
      return _stage == "positioning"
          ? "Face forward and hold still when all lines are green for capture"
          : "Turn your head as far as comfortable in one direction, then hold still for capture";
    }
    return "Hold still for capture";
  }

  /// runs pose estimation model on camera feed and initiates auto capture when working
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

      _handleAutoCapture();
    }
  }

  /// checks if user is in neutral or moved and displays correct red/green lines
  GuidanceState _guidanceState() {
    if (_keypoints == null) {
      return GuidanceState(isReady: false, lines: []);
    }

    if (widget.measurement == 'Cervical Rotation') {
      // return _guidanceForCervical();
      return _stage == "positioning"
          ? _guidanceForCervical()
          : _guidanceForCervicalMoved();
    } else if (widget.measurement == 'Lumbar Side Flexion') {
      // return _guidanceForLumbarSideFlexion();
      return _stage == "positioning"
          ? _guidanceForLumbarSideFlexion()
          : _guidanceForLumbarSideFlexionMoved();
    } else if (widget.measurement == 'Intermalleolar Distance') {
      return _guidanceForIntermalleolar();
    }

    return GuidanceState(isReady: false, lines: []);
  }

  /// displays red/green lines for level shoulders and nose central for cervical rotation
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

  /// displays red/green lines for cervical after user has moved as no longer needs line to nose
  GuidanceState _guidanceForCervicalMoved() {
    final leftShoulder = getKeypoint(_keypoints!, 'left_shoulder');
    final rightShoulder = getKeypoint(_keypoints!, 'right_shoulder');

    if (!hasGoodScore(leftShoulder) || !hasGoodScore(rightShoulder)) {
      return GuidanceState(isReady: false, lines: []);
    }

    final shoulderLevel = absDiff(getY(leftShoulder), getY(rightShoulder)) < 20;

    // final shoulderMidX = (getX(leftShoulder) + getX(rightShoulder)) / 2.0;
    // final noseCentered = absDiff(getX(nose), shoulderMidX) < 35;

    final isReady = shoulderLevel;

    return GuidanceState(
      isReady: isReady,
      lines: [
        GuideLine(
          startName: 'left_shoulder',
          endName: 'right_shoulder',
          color: shoulderLevel ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  /// displays red/green lines for real time posture guidance for Lumbar side felxion
  GuidanceState _guidanceForLumbarSideFlexion() {
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
    // final feetApartEnough = hipWidth > 0 && footDistance > hipWidth * 1.2;
    final distCm = _pxToCm(footDistance);
    final feetApartEnough = distCm != null && distCm >= 25 && distCm <= 35;

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

  /// displays red/green lines for after neutral position captured as shoulders no longer need to be level
  GuidanceState _guidanceForLumbarSideFlexionMoved() {
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
    // final feetApartEnough = hipWidth > 0 && footDistance > hipWidth * 1.2;
    final distCm = _pxToCm(footDistance);
    final feetApartEnough = distCm != null && distCm >= 25 && distCm <= 35;

    final isReady = kneesStraight && armsStraight && feetApartEnough;

    return GuidanceState(
      isReady: isReady,
      lines: [
        // GuideLine(
        //   startName: 'left_shoulder',
        //   endName: 'right_shoulder',
        //   color: shouldersLevel ? Colors.green : Colors.red,
        // ),
        // GuideLine(
        //   startName: 'left_hip',
        //   endName: 'right_hip',
        //   color: hipsLevel ? Colors.green : Colors.red,
        // ),
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

  /// Displays red/green lines for posture for Intermalleolar
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

    /// Threshold checks
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

  bool _isReadyNow() {
    return _guidanceState().isReady;
  }

  /// Calculates how far user has moved from neutral
  double? _movementAmountFromStart() {
    if (_capturedStart == null || _keypoints == null) {
      return null;
    }

    if (widget.measurement == "Lumbar Side Flexion") {
      final startWrist = getKeypoint(_capturedStart!, 'left_wrist');
      final startHip = getKeypoint(_capturedStart!, 'left_hip');
      final liveWrist = getKeypoint(_keypoints!, 'left_wrist');
      final liveHip = getKeypoint(_keypoints!, 'left_hip');

      if (startWrist == null ||
          startHip == null ||
          liveWrist == null ||
          liveHip == null) {
        return null;
      }

      final startOffset = getY(startWrist) - getY(startHip);
      final liveOffset = getY(liveWrist) - getY(liveHip);
      return (liveOffset - startOffset).abs();
    }

    if (widget.measurement == 'Cervical Rotation') {
      final startLeftShoulder = getKeypoint(_capturedStart!, 'left_shoulder');
      final startRightShoulder = getKeypoint(_capturedStart!, 'right_shoulder');
      final startNose = getKeypoint(_capturedStart!, 'nose');
      final liveLeftShoulder = getKeypoint(_keypoints!, 'left_shoulder');
      final liveRightShoulder = getKeypoint(_keypoints!, 'right_shoulder');
      final liveNose = getKeypoint(_keypoints!, 'nose');

      if (startLeftShoulder == null ||
          startRightShoulder == null ||
          startNose == null ||
          liveLeftShoulder == null ||
          liveRightShoulder == null ||
          liveNose == null) {
        return null;
      }

      final startMidX =
          (getX(startLeftShoulder) + getX(startRightShoulder)) / 2.0;
      final startMidY =
          (getY(startLeftShoulder) + getY(startRightShoulder)) / 2.0;
      final liveMidX = (getX(liveLeftShoulder) + getX(liveRightShoulder)) / 2.0;
      final liveMidY = (getY(liveLeftShoulder) + getY(liveRightShoulder)) / 2.0;

      final startAngle = atan2(
        getY(startNose) - startMidY,
        getX(startNose) - startMidX,
      );
      final liveAngle = atan2(
        getY(liveNose) - liveMidY,
        getX(liveNose) - liveMidX,
      );

      double deltaRad = liveAngle - startAngle;
      if (deltaRad > pi) deltaRad -= 2 * pi;
      if (deltaRad < -pi) deltaRad += 2 * pi;

      return (deltaRad * 180 / pi).abs();
    }

    if (widget.measurement == "Intermalleolar Distance") {
      final startRightAnkle = getKeypoint(_capturedStart!, 'right_ankle');
      final startLeftAnkle = getKeypoint(_capturedStart!, 'left_ankle');
      final liveRightAnkle = getKeypoint(_keypoints!, 'right_ankle');
      final liveLeftAnkle = getKeypoint(_keypoints!, 'left_ankle');

      if (startRightAnkle == null ||
          startLeftAnkle == null ||
          liveRightAnkle == null ||
          liveLeftAnkle == null) {
        return null;
      }

      final startDistance = distance(startLeftAnkle, startRightAnkle);
      final liveDistance = distance(liveRightAnkle, liveLeftAnkle);
      return (liveDistance - startDistance).abs();
    }

    return null;
  }

  /// checks user has moved from neutral before capturing second position
  double _movementThreshold() {
    if (widget.measurement == "Lumbar Side Flexion") {
      return 25;
    }
    if (widget.measurement == "Cervical Rotation") {
      return 10;
    }
    if (widget.measurement == "Intermalleolar Distance") {
      return 25;
    } // now redundant as only one position captured!
    return 20;
  }

  /// Displays 3 2 1 countdown on screen and records keypoint when captures
  Future<void> _startCountdownAndCapture() async {
    if (_countdownRunning) {
      return;
    }
    _countdownRunning = true;

    for (final v in [3, 2, 1]) {
      if (!mounted) return;
      setState(() {
        _countdownValue = v;
      });
      await Future.delayed(const Duration(seconds: 1));

      if (_stage == "positioning" && !_isReadyNow()) {
        _countdownRunning = false;
        setState(() {
          _countdownValue = null;
        });
        return;
      }

      if (_stage == "capturedStart") {
        final movement = _movementAmountFromStart();
        if (movement == null || movement < _movementThreshold()) {
          _countdownRunning = false;
          setState(() {
            _countdownValue = null;
          });
          return;
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _countdownValue = null;
    });

    _captureFrame();
    _countdownRunning = false;
  }

  /// gets ankle width for intermalleolar
  Future<void> _askForAnkleWidth() async {
    final controller = TextEditingController(
      text: _ankleWidthCm?.toStringAsFixed(1) ?? '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter ankle width (cm)"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: "e.g. 5.0"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              Navigator.pop(context, val);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      setState(() {
        _ankleWidthCm = result;
        _awaitingAnkleWidthAfterCalib = false;
        _isCalibrating = false;
        // _resultText =
        // "Ankle width set: ${_ankleWidthCm!.toStringAsFixed(1)} cm";
        _stage = "positioning";
      });
    }

    if (result == null || result <= 0) {
      setState(() {
        _awaitingAnkleWidthAfterCalib = true;
      });
      return;
    }
  }

  /// checks if posture correct and for long enough and if it can capture keypoints
  void _handleAutoCapture() {
    if (_isCalibrating || _stage == "cameraSetup") {
      return;
    }
    if (!_autoMode ||
        _keypoints == null ||
        _countdownRunning ||
        _stage == "result") {
      return;
    }

    if (_cmPerPixel == null && widget.measurement != "Cervical Rotation") {
      return;
    }

    if (widget.measurement == "Intermalleolar Distance") {
      final now = DateTime.now();

      if (_isReadyNow()) {
        _readySince ??= now;
        final ms = now.difference(_readySince!).inMilliseconds;
        if (ms >= 800) {
          _readySince = null;
          _startCountdownAndCapture();
        }
      } else {
        _readySince = null;
      }
      return;
    }

    final now = DateTime.now();

    if (_stage == "positioning") {
      if (_isReadyNow()) {
        _readySince ??= now;
        final ms = now.difference(_readySince!).inMilliseconds;
        if (ms >= 800) {
          _readySince = null;
          _startCountdownAndCapture();
        }
      } else {
        _readySince = null;
      }
      return;
    }

    if (_stage == "capturedStart") {
      if (!_isReadyNow()) {
        return;
      }

      final movement = _movementAmountFromStart();
      if (movement != null && movement >= _movementThreshold()) {
        _movementSince ??= now;
        final ms = now.difference(_movementSince!).inMilliseconds;
        if (ms >= 800) {
          _movementSince = null;
          _startCountdownAndCapture();
        }
      } else {
        _movementSince = null;
      }
    }
  }

  /// asks users to enter distance between two clikcd points
  void _askForDistance() async {
    final controller = TextEditingController();
    final RenderBox box =
        _previewKey.currentContext!.findRenderObject() as RenderBox;

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter distance (cm)"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "e.g. 30"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              Navigator.pop(context, val);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );

    if (result != null && _calibPoint1 != null && _calibPoint2 != null) {
      final p1 = _screenToVideo(_calibPoint1!, box.size);
      final p2 = _screenToVideo(_calibPoint2!, box.size);

      final dx = p1.dx - p2.dx;
      final dy = p1.dy - p2.dy;
      final pxDist = sqrt(dx * dx + dy * dy);

      setState(() {
        _cmPerPixel = result / pxDist;
        _calibPoint1 = null;
        _calibPoint2 = null;
      });

      if (widget.measurement == "Intermalleolar Distance") {
        setState(() {
          _awaitingAnkleWidthAfterCalib = true;
        });
        _askForAnkleWidth();
      } else {
        setState(() {
          _isCalibrating = false;
          _stage = "positioning";
        });
      }
    }
  }

  ///converts pixel distance to cm
  double? _pxToCm(double px) {
    if (_cmPerPixel == null) {
      // throw Exception("Calibration Failed");
      return null;
    }
    return px * _cmPerPixel!;
  }

  ///converts point clicked on screen to coordinate in frame
  Offset _screenToVideo(Offset screen, Size size) {
    final vw = _videoW!.toDouble();
    final vh = _videoH!.toDouble();

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

    final mirroredX = size.width - screen.dx;
    final x = (mirroredX - offsetX) / scale;
    // final x = (screen.dx - offsetX) / scale;
    final y = (screen.dy - offsetY) / scale;

    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final guidanceState = _guidanceState();
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Measuring: ${widget.measurement}'),
        backgroundColor: backgroundColor,
      ),
      body: Center(
        child: _initialized && _controller != null
            ? GestureDetector(
                key: _previewKey,
                onTapDown: (details) {
                  if (!_isCalibrating || _videoW == null || _videoH == null) {
                    return;
                  }

                  final box =
                      _previewKey.currentContext!.findRenderObject()
                          as RenderBox;
                  final local = box.globalToLocal(details.globalPosition);

                  setState(() {
                    if (_calibPoint1 == null) {
                      _calibPoint1 = local; //local -> videoPoint
                      _resultText =
                          "First point selected, Click the second point.";
                    } else {
                      _calibPoint2 = local;
                    }
                  });

                  if (_calibPoint1 != null && _calibPoint2 != null) {
                    _askForDistance();
                  }
                },
                child: Stack(
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
                            videoH: _videoH,
                            guidanceOn: _guidanceOn,
                            isReady: guidanceState.isReady,
                            guideLines: guidanceState.lines,
                            calibPoint1: _calibPoint1,
                            calibPoint2: _calibPoint2,
                          ),
                        ),
                      ),
                    ),

                    /// TITLE MESSAGE WIDGET
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _stageTitle(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),

                    /// TEXT MESSAGE WIDGET
                    Positioned(
                      bottom: 20,
                      left: 13,
                      right: 13,
                      child: Container(
                        width: 300,
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _displayMessage(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    /// CONTROL PANEL
                    /// Includes Calibration, Ankle Width, Reset Button and Guidance Switch
                    Positioned(
                      left: 13,
                      top: 92,
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            /// CALIBRATION BUTTON
                            /// Doesn't show if measuring Cervical Rotation
                            /// Now hidden
                            // if (widget.measurement != "Cervical Rotation")
                            //   ElevatedButton(
                            //     style: ElevatedButton.styleFrom(
                            //       backgroundColor: _cmPerPixel == null
                            //           ? Colors.grey[700]
                            //           // : primaryColor,
                            //           : Colors.green,
                            //       foregroundColor: Colors.white,
                            //       padding: const EdgeInsets.symmetric(
                            //         vertical: 14,
                            //       ),
                            //     ),
                            //     onPressed: () {
                            //       setState(() {
                            //         _isCalibrating = true;
                            //         _calibPoint1 = null;
                            //         _calibPoint2 = null;
                            //         _resultText = "";
                            //       });
                            //     },
                            //     child: Text(
                            //       _cmPerPixel == null
                            //           ? "Start Calibration"
                            //           : "Calibration: ${_cmPerPixel!.toStringAsFixed(2)}",
                            //     ),
                            //   ),
                            // if (widget.measurement != "Cervical Rotation")
                            //   const SizedBox(height: 10),

                            /// ANKLE WIDTH BUTTON
                            /// Only shows when measuring Intermalleolar Distance
                            /// now hidden
                            // if (widget.measurement == "Intermalleolar Distance")
                            //   ElevatedButton(
                            //     style: ElevatedButton.styleFrom(
                            //       backgroundColor: _ankleWidthCm == null
                            //           ? Colors.grey[700]
                            //           // : primaryColor,
                            //           : Colors.green,
                            //       foregroundColor: Colors.white,
                            //       padding: const EdgeInsets.symmetric(
                            //         vertical: 14,
                            //       ),
                            //     ),
                            //     onPressed: _askForAnkleWidth,
                            //     child: Text(
                            //       _ankleWidthCm == null
                            //           ? "Enter Ankle Width"
                            //           : "Ankle Width: ${_ankleWidthCm!.toStringAsFixed(1)} cm",
                            //     ),
                            //   ),
                            // if (widget.measurement == "Intermalleolar Distance")
                            //   const SizedBox(height: 10),

                            /// MANUAL MEASUREMENT BUTTON
                            /// Removed as not needed as now automated
                            // ElevatedButton(
                            //   onPressed: _isReadyNow() ? _captureFrame : null,
                            //   child: Text(
                            //     _stage == "positioning"
                            //         ? "Capture Start"
                            //         : "Capture End",
                            //   ),
                            // ),
                            // const SizedBox(height: 10),

                            /// CAMERA SET UP COMPLETE BUTTON
                            if (_stage == "cameraSetup")
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _resultText = "";

                                    if (widget.measurement ==
                                        "Cervical Rotation") {
                                      _stage = "positioning";
                                    } else {
                                      _stage = "calibration";
                                      _isCalibrating = true;
                                      _calibPoint1 = null;
                                      _calibPoint2 = null;
                                    }
                                  });
                                },
                                child: const Text("Camera Set Up Complete"),
                              ),
                            if (_stage == "cameraSetup")
                              const SizedBox(height: 10),

                            /// RESET BUTTON
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _reset,
                              child: const Text("Restart Measurement"),
                            ),
                            // const SizedBox(height: 10),

                            /// GUIDANCE OVERLAY SWITCH
                            /// Turned off as now redundant feature
                            // Container(
                            //   padding: const EdgeInsets.symmetric(
                            //     horizontal: 12,
                            //     vertical: 4,
                            //   ),
                            //   decoration: BoxDecoration(
                            //     color: Colors.white.withOpacity(0.08),
                            //     borderRadius: BorderRadius.circular(12),
                            //   ),
                            //   child: Row(
                            //     mainAxisAlignment:
                            //         MainAxisAlignment.spaceBetween,
                            //     children: [
                            //       const Text(
                            //         "Guidance",
                            //         style: TextStyle(color: Colors.white),
                            //       ),
                            //       Switch(
                            //         value: _guidanceOn,
                            //         activeColor: Colors.green,
                            //         // inactiveColor: Colors.red,
                            //         onChanged: (val) {
                            //           setState(() {
                            //             _guidanceOn = val;
                            //           });
                            //         },
                            //       ),
                            //     ],
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ),

                    // if (_stage == "result")
                    //   Positioned(
                    //     bottom: 110,
                    //     right: 20,
                    //     child: ElevatedButton(
                    //       style: ElevatedButton.styleFrom(
                    //         backgroundColor: Colors.green,
                    //         foregroundColor: Colors.white,
                    //         padding: const EdgeInsets.symmetric(
                    //           horizontal: 20,
                    //           vertical: 14,
                    //         ),
                    //       ),
                    //       onPressed: () {
                    //         Navigator.pop(contex);
                    //       },
                    //       child: const Text("Save & Return"),
                    //     ),
                    //   ),

                    /// COUNTDOWN
                    /// Displays 3 2 1 on screen
                    if (_countdownValue != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              _countdownValue.toString(),
                              style: const TextStyle(
                                color: primaryColor,
                                fontSize: 72,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
  final Offset? calibPoint1;
  final Offset? calibPoint2;
  static const primaryColor = Color(0xFF4FF6F5);

  GuideOverlayPainter({
    this.keypoints,
    this.videoW,
    this.videoH,
    required this.guidanceOn,
    required this.isReady,
    required this.guideLines,
    required this.calibPoint1,
    required this.calibPoint2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Box frame
    if (!guidanceOn) {
      return;
    }

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

    if (keypoints == null || videoW == null || videoH == null) {
      return;
    }
    if (videoW == 0 || videoH == 0) {
      return;
    }

    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    if (calibPoint1 != null) {
      canvas.drawCircle(calibPoint1!, 4, dotPaint);
    }

    if (calibPoint2 != null) {
      canvas.drawCircle(calibPoint2!, 4, dotPaint);

      if (calibPoint1 != null) {
        final linePaint = Paint()
          ..color = primaryColor
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

        canvas.drawLine(calibPoint1!, calibPoint2!, linePaint);
      }
    }

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
      if (keypoints == null) {
        return null;
      }

      final kp = getKeypoint(keypoints!, name);
      if (kp == null || !hasGoodScore(kp)) {
        return null;
      }

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
  if (kp == null) {
    return false;
  }
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

  if (mag1 == 0 || mag2 == 0) {
    return 0;
  }

  final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
  return acos(cosTheta) * 180 / pi;
}

double absDiff(double a, double b) => (a - b).abs();
