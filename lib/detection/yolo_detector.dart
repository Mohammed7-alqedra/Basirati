import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// One detected object. The box is normalized (0..1) in the upright
/// (portrait) camera image.
class Detection {
  final int classId;
  final String label;
  final double score;
  final double left, top, right, bottom;

  /// true = obstacle (warned while walking); false = info object (said on request)
  final bool isObstacle;

  Detection({
    required this.classId,
    required this.label,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.isObstacle,
  });

  double get centerX => (left + right) / 2;

  double get width => right - left;

  double get height => bottom - top;

  /// Simple three-zone direction from the box center.
  String get direction {
    if (centerX < 1 / 3) return 'left';
    if (centerX > 2 / 3) return 'right';
    return 'ahead';
  }
}

/// Runs the YOLO model (assets/yolo11n.tflite, input [1, 3, 320, 320],
/// output [1, 84, 2100]) on live camera frames.
class YoloDetector {
  // OBSTACLES – warned about while the user walks:
  // person, bicycle, car, motorcycle, bus, truck, bench, backpack,
  // handbag, suitcase, chair, couch, potted plant, dining table
  static const Set<int> obstacleClasses = {
    0,
    1,
    2,
    3,
    5,
    7,
    13,
    24,
    26,
    28,
    56,
    57,
    58,
    60,
  };

  // INFO OBJECTS – said only when the user asks "what's in front of me?":
  // bottle, cup, toilet, tv, laptop, mouse, keyboard, cell phone,
  // microwave, sink, refrigerator, book, clock
  static const Set<int> infoClasses = {
    39,
    41,
    61,
    62,
    63,
    64,
    66,
    67,
    68,
    71,
    72,
    73,
    74,
  };

  final double confThreshold;
  final double iouThreshold;

  late Interpreter _interpreter;
  late List<String> _labels;
  late int _inputSize;
  late bool _inputChannelsFirst; // [1, 3, H, W] vs [1, H, W, 3]
  late bool _outputChannelsFirst; // [1, 84, N] vs [1, N, 84]
  late int _numChannels;
  late int _numBoxes;
  late List<int> _classesToCheck;
  late Float32List _input;
  late Float32List _output;

  YoloDetector({this.confThreshold = 0.4, this.iouThreshold = 0.45});

  Future<void> load() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(
      'assets/yolo11n.tflite',
      options: options,
    );

    final labelsText = await rootBundle.loadString('assets/labels.txt');
    _labels = labelsText
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final inShape = _interpreter.getInputTensor(0).shape;
    _inputChannelsFirst = inShape[1] == 3;
    _inputSize = _inputChannelsFirst ? inShape[2] : inShape[1];

    final outShape = _interpreter.getOutputTensor(0).shape;
    _outputChannelsFirst = outShape[1] < outShape[2];
    _numChannels = _outputChannelsFirst ? outShape[1] : outShape[2];
    _numBoxes = _outputChannelsFirst ? outShape[2] : outShape[1];

    _classesToCheck = {
      ...obstacleClasses,
      ...infoClasses,
    }.where((c) => c < _numChannels - 4).toList();

    _input = Float32List(_inputSize * _inputSize * 3);
    _output = Float32List(_numChannels * _numBoxes);
  }

  /// Detects objects in one camera frame.
  /// [rotation] is the camera sensor orientation (usually 90 on Android phones).
  List<Detection> detect(CameraImage image, int rotation) {
    final stopwatch = Stopwatch()..start();

    _fillInput(image, rotation);
    _interpreter.run(_input.buffer, _output.buffer);

    final detections = _nonMaxSuppression(_readCandidates());

    stopwatch.stop();

    final ms = stopwatch.elapsedMilliseconds;

    return detections;
  }

  // ---------- 1. Camera frame (YUV) -> model input ----------
  // Only the 320 x 320 pixels the model needs are converted, which keeps it fast.
  void _fillInput(CameraImage img, int rotation) {
    final w = img.width, h = img.height;
    final yPlane = img.planes[0],
        uPlane = img.planes[1],
        vPlane = img.planes[2];
    final yRow = yPlane.bytesPerRow;
    final uRow = uPlane.bytesPerRow, vRow = vPlane.bytesPerRow;
    final uPix = uPlane.bytesPerPixel ?? 1, vPix = vPlane.bytesPerPixel ?? 1;
    final yBytes = yPlane.bytes, uBytes = uPlane.bytes, vBytes = vPlane.bytes;

    final rotated = rotation == 90 || rotation == 270;
    final uprightW = rotated ? h : w;
    final uprightH = rotated ? w : h;
    final s = _inputSize;
    final area = s * s;

    for (int j = 0; j < s; j++) {
      final uy = (j * uprightH) ~/ s;
      for (int i = 0; i < s; i++) {
        final ux = (i * uprightW) ~/ s;

        // Map the upright pixel back to the sensor image.
        int sx, sy;
        switch (rotation) {
          case 90:
            sx = uy;
            sy = h - 1 - ux;
            break;
          case 180:
            sx = w - 1 - ux;
            sy = h - 1 - uy;
            break;
          case 270:
            sx = w - 1 - uy;
            sy = ux;
            break;
          default:
            sx = ux;
            sy = uy;
        }

        final y = yBytes[sy * yRow + sx];
        final u = uBytes[(sy >> 1) * uRow + (sx >> 1) * uPix] - 128;
        final v = vBytes[(sy >> 1) * vRow + (sx >> 1) * vPix] - 128;

        final r = _clamp(y + 1.402 * v) / 255.0;
        final g = _clamp(y - 0.344136 * u - 0.714136 * v) / 255.0;
        final b = _clamp(y + 1.772 * u) / 255.0;

        final idx = j * s + i;
        if (_inputChannelsFirst) {
          // Planar: all red, then all green, then all blue.
          _input[idx] = r;
          _input[area + idx] = g;
          _input[2 * area + idx] = b;
        } else {
          final k = idx * 3;
          _input[k] = r;
          _input[k + 1] = g;
          _input[k + 2] = b;
        }
      }
    }
  }

  static double _clamp(double x) => x < 0 ? 0 : (x > 255 ? 255 : x);

  // ---------- 2. Model output -> candidate boxes ----------
  double _value(int channel, int box) => _outputChannelsFirst
      ? _output[channel * _numBoxes + box]
      : _output[box * _numChannels + channel];

  List<Detection> _readCandidates() {
    final candidates = <Detection>[];
    for (int i = 0; i < _numBoxes; i++) {
      int bestClass = -1;
      double bestScore = confThreshold;
      for (final c in _classesToCheck) {
        final s = _value(4 + c, i);
        if (s > bestScore) {
          bestScore = s;
          bestClass = c;
        }
      }
      if (bestClass < 0) continue;

      double cx = _value(0, i), cy = _value(1, i);
      double bw = _value(2, i), bh = _value(3, i);
      // Boxes are usually normalized; if they come in pixels, normalize them.
      if (cx > 1.5 || cy > 1.5 || bw > 1.5 || bh > 1.5) {
        cx /= _inputSize;
        cy /= _inputSize;
        bw /= _inputSize;
        bh /= _inputSize;
      }
      candidates.add(
        Detection(
          classId: bestClass,
          label: bestClass < _labels.length ? _labels[bestClass] : 'object',
          score: bestScore,
          left: cx - bw / 2,
          top: cy - bh / 2,
          right: cx + bw / 2,
          bottom: cy + bh / 2,
          isObstacle: obstacleClasses.contains(bestClass),
        ),
      );
    }
    return candidates;
  }

  // ---------- 3. Remove duplicate boxes (NMS) ----------
  List<Detection> _nonMaxSuppression(List<Detection> detections) {
    final remaining = [...detections]
      ..sort((a, b) => b.score.compareTo(a.score));
    final kept = <Detection>[];
    while (remaining.isNotEmpty) {
      final best = remaining.removeAt(0);
      kept.add(best);
      remaining.removeWhere(
        (d) => d.classId == best.classId && _iou(d, best) > iouThreshold,
      );
    }
    return kept;
  }

  double _iou(Detection a, Detection b) {
    final left = a.left > b.left ? a.left : b.left;
    final top = a.top > b.top ? a.top : b.top;
    final right = a.right < b.right ? a.right : b.right;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    final iw = right - left, ih = bottom - top;
    final inter = (iw > 0 ? iw : 0) * (ih > 0 ? ih : 0);
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  void close() => _interpreter.close();
}
