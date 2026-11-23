import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// The exact model family used by Maya alsuos.ipynb:
/// YOLO26n (COCO objects) + Depth Anything V2 Metric Hypersim Small.
/// Unlike the Colab notebook, inference happens entirely on Android.
class OfflineMayaPipeline {
  OfflineMayaPipeline._(this._yolo, this._depth, this._depthSize);

  final YOLO _yolo;
  final Interpreter _depth;
  final int _depthSize;

  // Values copied from Maya alsuos.ipynb; accuracy is NOT validated.
  static const double scaleFactor = 1.05;
  static const double offset = -0.10;
  static const double boxInset = 0.20;

  static Future<OfflineMayaPipeline> load(String depthModelPath) async {
    final yolo = YOLO(modelPath: 'yolo26n', task: YOLOTask.detect);
    Interpreter? depth;
    try {
      final ok = await yolo.loadModel(); // downloads YOLO26n only on first use
      if (!ok) throw StateError('YOLO26n could not be loaded.');
      depth = await Interpreter.fromFile(
        // The depth TFLite export must match the notebook's Hypersim Small weights.
        // It is downloaded separately and saved for offline operation.
        FileModel(depthModelPath).file,
        options: InterpreterOptions()..threads = 2,
      );

      final input = depth.getInputTensor(0).shape;
      final output = depth.getOutputTensor(0).shape;
      if (input.length != 4 || input[0] != 1 || input[1] != 3 ||
          input[2] != 518 || input[3] != 518 ||
          output.length != 3 || output[0] != 1 ||
          output[1] != 518 || output[2] != 518) {
        throw StateError('Wrong Depth Anything V2 model tensor shape: $input -> $output');
      }

      return OfflineMayaPipeline._(yolo, depth, 518);
    } catch (_) {
      depth?.close();
      await yolo.dispose();
      rethrow;
    }
  }

  Future<MayaFrame> process(Uint8List jpeg) async {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) throw const FormatException('Camera image is not a JPEG');
    // The normalized boxes from YOLO reference the upright original image.
    final full = img.bakeOrientation(decoded);

    final yoloOutput = await _yolo.predict(jpeg, confidenceThreshold: 0.25);
    final detectionsRaw = yoloOutput['detections'];
    final detections = <YOLOResult>[];
    if (detectionsRaw is List) {
      for (final item in detectionsRaw) {
        if (item is Map) detections.add(YOLOResult.fromMap(item));
      }
    }

    // Fixed-size Android export: crop to square and preserve the 518x518
    // pixel-to-depth coordinate mapping, including cropping offsets.
    final side = math.min(full.width, full.height);
    final cropX = (full.width - side) ~/ 2;
    final cropY = (full.height - side) ~/ 2;
    final cropped = img.copyCrop(
      full, x: cropX, y: cropY, width: side, height: side,
    );
    final resized = img.copyResize(
      cropped,
      width: _depthSize,
      height: _depthSize,
      interpolation: img.Interpolation.cubic,
    );

    final input = Float32List(3 * _depthSize * _depthSize);
    final output = Float32List(_depthSize * _depthSize);
    final area = _depthSize * _depthSize;
    for (var y = 0; y < _depthSize; y++) {
      for (var x = 0; x < _depthSize; x++) {
        final p = resized.getPixel(x, y);
        final i = y * _depthSize + x;
        input[i] = (p.r.toDouble() / 255 - 0.485) / 0.229;
        input[area + i] = (p.g.toDouble() / 255 - 0.456) / 0.224;
        input[2 * area + i] = (p.b.toDouble() / 255 - 0.406) / 0.225;
      }
    }
    _depth.run(input.buffer, output.buffer);

    final objects = <MayaObject>[];
    for (final detection in detections) {
      final box = detection.normalizedBox;
      if (box.width <= 0 || box.height <= 0) continue;
      final raw = medianDepthInsideBox(
        output,
        _depthSize,
        _depthSize,
        box,
        imageWidth: full.width,
        imageHeight: full.height,
        cropX: cropX,
        cropY: cropY,
        cropSize: side,
      );
      objects.add(MayaObject(
        name: detection.className,
        confidence: detection.confidence,
        box: box,
        rawDepthMeters: raw,
        estimatedMeters: raw == null ? null : math.max(0, scaleFactor * raw + offset),
      ));
    }
    return MayaFrame(jpeg: jpeg, width: full.width, height: full.height, objects: objects);
  }

  Future<void> close() async {
    _depth.close();
    await _yolo.dispose();
  }

  /// Central 60% of the box, matching Maya's 20% inset and valid-depth median.
  /// Returns null when the box is outside the center-cropped depth image.
  static double? medianDepthInsideBox(
    Float32List depth,
    int width,
    int height,
    Rect normalizedBox, {
    required int imageWidth,
    required int imageHeight,
    required int cropX,
    required int cropY,
    required int cropSize,
  }) {
    if (depth.length != width * height || normalizedBox.width <= 0 ||
        normalizedBox.height <= 0) return null;

    final l = (normalizedBox.left + normalizedBox.width * boxInset) * imageWidth;
    final r = (normalizedBox.right - normalizedBox.width * boxInset) * imageWidth;
    final t = (normalizedBox.top + normalizedBox.height * boxInset) * imageHeight;
    final b = (normalizedBox.bottom - normalizedBox.height * boxInset) * imageHeight;

    final x1 = (((l - cropX) / cropSize) * width).floor().clamp(0, width);
    final x2 = (((r - cropX) / cropSize) * width).ceil().clamp(0, width);
    final y1 = (((t - cropY) / cropSize) * height).floor().clamp(0, height);
    final y2 = (((b - cropY) / cropSize) * height).ceil().clamp(0, height);
    if (x2 <= x1 || y2 <= y1) return null;
    final valid = <double>[];
    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        final v = depth[y * width + x];
        if (v.isFinite && v > 0) valid.add(v);
      }
    }
    if (valid.isEmpty) return null;
    valid.sort();
    final mid = valid.length ~/ 2;
    return valid.length.isOdd ? valid[mid] : (valid[mid - 1] + valid[mid]) / 2.0;
  }
}

class MayaObject {
  const MayaObject({
    required this.name,
    required this.confidence,
    required this.box,
    required this.rawDepthMeters,
    required this.estimatedMeters,
  });

  final String name;
  final double confidence;
  final Rect box;
  final double? rawDepthMeters;
  final double? estimatedMeters;
}

class MayaFrame {
  const MayaFrame({required this.jpeg, required this.width, required this.height, required this.objects});

  final Uint8List jpeg;
  final int width;
  final int height;
  final List<MayaObject> objects;
}

/// Minimal wrapper to keep the model file path typed at the Flutter boundary.
/// This is NOT another model.
class FileModel {
  FileModel(String path) : file = File(path);
  final File file;
}
