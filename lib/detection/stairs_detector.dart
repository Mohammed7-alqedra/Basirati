import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'yolo_detector.dart';

/// Runs the stairs model (assets/stairs_float32.tflite, input [1, 3, 320, 320],
/// output [1, 5, 2100]: 4 box values + 1 class "stairs") on live camera frames.
/// Same steps as YoloDetector, with one class. YoloDetector is not changed.
class StairsDetector {
  static const String modelPath = 'assets/stairs_float32.tflite';
  static const String labelsPath = 'assets/stairs_labels.txt';

  final double confThreshold;
  final double iouThreshold;

  Interpreter? _interpreter;
  String _label = 'stairs';
  late int _inputSize;
  late bool _inputChannelsFirst; // [1, 3, H, W] vs [1, H, W, 3]
  late bool _outputChannelsFirst; // [1, 5, N] vs [1, N, 5]
  late int _numChannels;
  late int _numBoxes;
  late Float32List _input;
  late Float32List _output;

  StairsDetector({this.confThreshold = 0.3, this.iouThreshold = 0.45});

  Future<void> load() async {
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(modelPath, options: options);

    final inShape = interpreter.getInputTensor(0).shape;
    _inputChannelsFirst = inShape[1] == 3;
    _inputSize = _inputChannelsFirst ? inShape[2] : inShape[1];

    final outShape = interpreter.getOutputTensor(0).shape;
    _outputChannelsFirst = outShape[1] < outShape[2];
    _numChannels = _outputChannelsFirst ? outShape[1] : outShape[2];
    _numBoxes = _outputChannelsFirst ? outShape[2] : outShape[1];
    if (_numChannels < 5) {
      interpreter.close();
      throw StateError('Stairs model output has $_numChannels values, expected 5');
    }

    // The label file is optional: without it the label is simply "stairs".
    try {
      final text = await rootBundle.loadString(labelsPath);
      final first = text.split('\n').map((s) => s.trim()).firstWhere(
            (s) => s.isNotEmpty,
            orElse: () => 'stairs',
          );
      _label = first;
    } catch (_) {
      _label = 'stairs';
    }

    _input = Float32List(_inputSize * _inputSize * 3);
    _output = Float32List(_numChannels * _numBoxes);
    _interpreter = interpreter;
  }

  bool get isLoaded => _interpreter != null;

  /// Finds stairs in one camera frame. Boxes are normalized (0..1),
  /// like YoloDetector, so OverlayPainter can draw them.
  List<Detection> detect(CameraImage image, int rotation) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];
    _fillInput(image, rotation);
    interpreter.run(_input.buffer, _output.buffer);
    return _nonMaxSuppression(_readCandidates());
  }

  // ---------- 1. Camera frame (YUV) -> model input ----------
  // Same conversion as YoloDetector._fillInput.
  void _fillInput(CameraImage img, int rotation) {
    final w = img.width, h = img.height;
    final yPlane = img.planes[0], uPlane = img.planes[1], vPlane = img.planes[2];
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
      final score = _value(4, i); // class 0 = stairs
      if (score <= confThreshold) continue;

      double cx = _value(0, i), cy = _value(1, i);
      double bw = _value(2, i), bh = _value(3, i);
      // Boxes are usually normalized; if they come in pixels, normalize them.
      if (cx > 1.5 || cy > 1.5 || bw > 1.5 || bh > 1.5) {
        cx /= _inputSize;
        cy /= _inputSize;
        bw /= _inputSize;
        bh /= _inputSize;
      }
      candidates.add(Detection(
        classId: 0,
        label: _label,
        score: score,
        left: cx - bw / 2,
        top: cy - bh / 2,
        right: cx + bw / 2,
        bottom: cy + bh / 2,
        isObstacle: true,
      ));
    }
    return candidates;
  }

  // ---------- 3. Remove duplicate boxes (NMS) ----------
  List<Detection> _nonMaxSuppression(List<Detection> detections) {
    final remaining = [...detections]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <Detection>[];
    while (remaining.isNotEmpty) {
      final best = remaining.removeAt(0);
      kept.add(best);
      remaining.removeWhere((d) => _iou(d, best) > iouThreshold);
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

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Decides when to say "Stairs ahead".
/// - Speaks only when stairs were found in 2 of the last 3 stairs checks
///   (one wrong frame is not enough).
/// - Says it once, then stays quiet while the stairs are still around.
/// - After no stairs for [memory], the next stairs are announced again.
class StairsAlert {
  final Duration memory;
  final List<bool> _history = [];
  DateTime? _lastConfirmed;
  bool _announced = false;

  StairsAlert({this.memory = const Duration(seconds: 4)});

  /// true while stairs are confirmed or were confirmed less than [memory] ago.
  bool get active => _announced;

  /// Call after every stairs check. Returns a sentence to say, or null.
  String? update(List<Detection> stairs, DateTime now) {
    _history.add(stairs.isNotEmpty);
    if (_history.length > 3) _history.removeAt(0);
    final confirmed = _history.where((found) => found).length >= 2;

    if (confirmed) {
      _lastConfirmed = now;
      if (_announced) return null;
      _announced = true;
      if (stairs.isEmpty) return 'Stairs ahead';
      final best = stairs.reduce((a, b) => a.score >= b.score ? a : b);
      switch (best.direction) {
        case 'left':
          return 'Stairs on your left';
        case 'right':
          return 'Stairs on your right';
        default:
          return 'Stairs ahead';
      }
    }

    final last = _lastConfirmed;
    if (_announced && last != null && now.difference(last) > memory) {
      _announced = false;
    }
    return null;
  }
}
