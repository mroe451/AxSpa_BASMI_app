@JS()
library pose_service;

import 'dart:js_util' as js_util;
import 'package:js/js.dart';

@JS('initPose')
external Object _initPose();

@JS('detectPose')
external Object _detectPose(Object videoElement);

Future<void> initPose() async {
  await js_util.promiseToFuture(_initPose());
}

Future<dynamic> detectPose(Object videoElement) async {
  return await js_util.promiseToFuture(_detectPose(videoElement));
}
