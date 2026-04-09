import 'package:flutter/material.dart';
import 'camera_screen.dart';

class BasmiMenu extends StatefulWidget {
  const BasmiMenu({super.key});

  @override
  State<BasmiMenu> createState() => _BasmiMenuState();
}

class _BasmiMenuState extends State<BasmiMenu> {
  final List<String> measurements = const [
    'Cervical Rotation',
    'Lateral Flexion',
    // 'Lumbar Flexion',
    'Intermalleolar Distance',
    // 'Tragus-to-Wall Distance',
  ];

  final Map<String, String> recordedResults = {};

  final TextEditingController lumbarFlexionController = TextEditingController();
  final TextEditingController tragusWallController = TextEditingController();

  String basmiScoreResult = "";

  static const Color primaryColor = Color(0xFF4FF6F5);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color textColor = Color(0xFF111827);
  static const Color subtitleColor = Color(0xFF6B7280);
  static const Color cardBorderColor = Color(0xFFE5E7EB);
  static const Color successColor = Color(0xFF16A34A);

  void _saveMeasurement(String measurement, String result) {
    setState(() {
      recordedResults[measurement] = result;
    });
  }

  @override
  void dispose() {
    lumbarFlexionController.dispose();
    tragusWallController.dispose();
    super.dispose();
  }

  void _calculateBasmiScore() {
    final cervicalRaw = _extractNumber(recordedResults['Cervical Rotation']);
    final lateralRaw = _extractNumber(recordedResults['Lateral Flexion']);
    final intermalleolarRaw = _extractNumber(
      recordedResults['Intermalleolar Distance'],
    );

    final lumbarRaw = double.tryParse(lumbarFlexionController.text.trim());
    final tragusRaw = double.tryParse(tragusWallController.text.trim());

    if (cervicalRaw == null ||
        lateralRaw == null ||
        intermalleolarRaw == null ||
        lumbarRaw == null ||
        tragusRaw == null) {
      setState(() {
        basmiScoreResult =
            "Please complete the 3 measured values and enter the 2 manual measurements.";
      });
      return;
    }

    final cervicalScore = _scoreCervicalRotation(cervicalRaw);
    final lateralScore = _scoreLateralFlexion(lateralRaw);
    final lumbarScore = _scoreLumbarFlexion(lumbarRaw);
    final intermalleolarScore = _scoreIntermalleolar(intermalleolarRaw);
    final tragusScore = _scoreTragusToWall(tragusRaw);

    final total =
        cervicalScore +
        lateralScore +
        lumbarScore +
        intermalleolarScore +
        tragusScore;
    final basmi = total / 5.0;

    setState(() {
      basmiScoreResult =
          "BASMI Score: ${basmi.toStringAsFixed(2)}\n"
          "Component scores - "
          "Cervical: $cervicalScore, "
          "Lateral: $lateralScore, "
          "Lumbar: $lumbarScore, "
          "Intermalleolar: $intermalleolarScore, "
          "Tragus-to-Wall: $tragusScore";
    });
  }

  double? _extractNumber(String? text) {
    if (text == null) {
      return null;
    }

    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(text);
    if (match == null) {
      return null;
    }

    return double.tryParse(match.group(0)!);
  }

  int _scoreCervicalRotation(double value) {
    if (value >= 85) return 0;
    if (value >= 76.6) return 1;
    if (value >= 68.1) return 2;
    if (value >= 59.6) return 3;
    if (value >= 51.1) return 4;
    if (value >= 42.6) return 5;
    if (value >= 34.1) return 6;
    if (value >= 25.6) return 7;
    if (value >= 17.1) return 8;
    if (value >= 8.6) return 9;
    return 10;
  }

  int _scoreLateralFlexion(double value) {
    if (value >= 20) return 0;
    if (value >= 18) return 1;
    if (value >= 15.9) return 2;
    if (value >= 13.8) return 3;
    if (value >= 11.7) return 4;
    if (value >= 9.6) return 5;
    if (value >= 7.5) return 6;
    if (value >= 5.4) return 7;
    if (value >= 3.3) return 8;
    if (value >= 1.2) return 9;
    return 10;
  }

  int _scoreLumbarFlexion(double value) {
    if (value > 7.0) return 0;
    if (value >= 6.4) return 1;
    if (value >= 5.7) return 2;
    if (value >= 5.0) return 3;
    if (value >= 4.3) return 4;
    if (value >= 3.6) return 5;
    if (value >= 2.9) return 6;
    if (value >= 2.2) return 7;
    if (value >= 1.5) return 8;
    if (value >= 0.8) return 9;
    return 10;
  }

  int _scoreIntermalleolar(double value) {
    if (value >= 120) return 0;
    if (value >= 110) return 1;
    if (value >= 100) return 2;
    if (value >= 90) return 3;
    if (value >= 80) return 4;
    if (value >= 70) return 5;
    if (value >= 60) return 6;
    if (value >= 50) return 7;
    if (value >= 40) return 8;
    if (value >= 30) return 9;
    return 10;
  }

  int _scoreTragusToWall(double value) {
    if (value <= 10) return 0;
    if (value <= 12.9) return 1;
    if (value <= 15.9) return 2;
    if (value <= 18.9) return 3;
    if (value <= 21.9) return 4;
    if (value <= 24.9) return 5;
    if (value <= 27.9) return 6;
    if (value <= 30.9) return 7;
    if (value <= 33.9) return 8;
    if (value <= 36.9) return 9;
    return 10;
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: subtitleColor,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _measurementCard(String measurement) {
    final saved = recordedResults[measurement];
    final isComplete = saved != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete ? successColor.withOpacity(0.35) : cardBorderColor,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraScreen(
                measurement: measurement,
                onMeasurementSaved: _saveMeasurement,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isComplete ? Icons.check_rounded : Icons.straighten_rounded,
                  color: isComplete ? successColor : textColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      measurement,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isComplete ? saved : "Not yet recorded",
                      style: TextStyle(
                        fontSize: 14,
                        color: isComplete ? successColor : subtitleColor,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: subtitleColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualInputField({
    required String label,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cardBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cardBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _resultCard() {
    if (basmiScoreResult.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        basmiScoreResult,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'BASMI Assessment',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: backgroundColor,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              children: [
                _sectionTitle(
                  "Camera based measurements",
                  subtitle:
                      "Complete the three guided measurements below using the camera.",
                ),
                const SizedBox(height: 18),

                ...measurements.map(_measurementCard),

                const SizedBox(height: 18),

                _sectionTitle(
                  "Manual Measurements",
                  subtitle:
                      "Enter the remaining BASMI values measured manually.",
                ),
                const SizedBox(height: 18),

                _manualInputField(
                  label: "Lumbar Flexion (cm)",
                  controller: lumbarFlexionController,
                ),
                _manualInputField(
                  label: "Tragus-to-Wall Distance (cm)",
                  controller: tragusWallController,
                ),
                const SizedBox(height: 10),

                SizedBox(height: 10),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: textColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 1,
                    ),
                    onPressed: _calculateBasmiScore,
                    child: const Text(
                      "Calculate BASMI Score",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                _resultCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     appBar: AppBar(title: const Text('Select Measurement')),
  //     body: ListView(
  //       padding: const EdgeInsets.all(8),
  //       children: [
  //         ...measurements.map((measurement) {
  //           final saved = recordedResults[measurement];
  //           //   }
  //           //   )
  //           // ],
  //           // itemCount: measurements.length,
  //           // itemBuilder: (context, index) {
  //           //   final measurement = measurements[index];
  //           //   final saved = recordedResults[measurement];
  //
  //           return Padding(
  //             padding: const EdgeInsets.only(bottom: 8.0),
  //             child: ElevatedButton(
  //               onPressed: () {
  //                 Navigator.push(
  //                   context,
  //                   MaterialPageRoute(
  //                     builder: (_) => CameraScreen(
  //                       measurement: measurement,
  //                       onMeasurementSaved: _saveMeasurement,
  //                     ),
  //                   ),
  //                 );
  //               },
  //
  //               child: Padding(
  //                 padding: const EdgeInsets.symmetric(vertical: 16.0),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Text(measurement, style: const TextStyle(fontSize: 18)),
  //                     if (saved != null) ...[
  //                       const SizedBox(height: 6),
  //                       Text(
  //                         "Saved result: $saved",
  //                         style: const TextStyle(fontSize: 14),
  //                       ),
  //                     ],
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           );
  //         }).toList(),
  //
  //         const SizedBox(height: 20),
  //         const Text(
  //           "Enter Remaining Measurements",
  //           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  //         ),
  //         const SizedBox(height: 12),
  //
  //         TextField(
  //           controller: lumbarFlexionController,
  //           keyboardType: const TextInputType.numberWithOptions(decimal: true),
  //           decoration: const InputDecoration(
  //             labelText: "Lumbar Flexion (cm)",
  //             border: OutlineInputBorder(),
  //           ),
  //         ),
  //         const SizedBox(height: 12),
  //
  //         TextField(
  //           controller: tragusWallController,
  //           keyboardType: const TextInputType.numberWithOptions(decimal: true),
  //           decoration: const InputDecoration(
  //             labelText: "Tragus-to-Wall Distance (cm)",
  //             border: OutlineInputBorder(),
  //           ),
  //         ),
  //         const SizedBox(height: 16),
  //
  //         ElevatedButton(
  //           onPressed: _calculateBasmiScore,
  //           child: const Text("Calculate BASMI Score"),
  //         ),
  //         const SizedBox(height: 16),
  //
  //         Text(
  //           basmiScoreResult,
  //           style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}
