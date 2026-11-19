import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../detection/yolo_detector.dart';

/// The uploaded notebook's measurement procedure, ported from Python.
/// Checkpoint equivalence and camera preprocessing must still be verified.
/// Do not use this prototype for obstacle safety warnings or navigation.
class DepthReading {
  final double rawMeters;
  final double correctedMeters;

  const DepthReading(this.rawMeters, this.correctedMeters);
}

class DepthEstimator {
  /// Coefficients copied exactly from Untitled11 (2).ipynb (Cell 3).
  /// These are test values, not validated calibration for the S25 Ultra.
  static const double slope = 0.6341037631666971;
  static const double intercept = 0.401649701699875;
  Interpreter? _interpreter;
  late Float32List _input;
  late Float32List _output;
  late int _width, _height, _outputWidth, _outputHeight;
  bool _hasDepth = false;
  double _cropLeft = 0, _cropTop = 0, _cropWidth = 1, _cropHeight = 1;
  bool get hasDepth => _hasDepth;

  Future<void> load() async {
    final interpreter = await Interpreter.fromAsset(
      'assets/depth_indoor.tflite',
      options: InterpreterOptions()..threads = 4,
    );
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (inputShape.length != 4 || inputShape[1] != 3 ||
        outputShape.length != 3) {
      interpreter.close();
      throw StateError('Unexpected depth model tensor layout');
    }
    _height = inputShape[2];
    _width = inputShape[3];
    _outputHeight = outputShape[1];
    _outputWidth = outputShape[2];
    _input = Float32List(_height * _width * 3);
    _output = Float32List(_outputHeight * _outputWidth);
    _interpreter = interpreter;
  }

  void update(CameraImage image, int rotation) {
    final interpreter = _interpreter;
    if (interpreter == null) return;
    if (image.planes.length < 3) {
      throw StateError('Expected a YUV420 camera image');
    }
    _prepare(image, rotation);
    interpreter.run(_input.buffer, _output.buffer);
    _hasDepth = true;
  }

  /// Match notebook: median of valid depth pixels in the central 60%
  /// of a YOLO bounding box, followed by slope*raw + intercept.
  DepthReading? readingFor(Detection detection) {
    if (!_hasDepth || detection.width <= 0 || detection.height <= 0) {
      return null;
    }

    const inset = 0.20;
    // YOLO boxes refer to the full upright frame; depth uses a center crop.
    final left = (detection.left + detection.width * inset - _cropLeft) / _cropWidth;
    final right = (detection.right - detection.width * inset - _cropLeft) / _cropWidth;
    final top = (detection.top + detection.height * inset - _cropTop) / _cropHeight;
    final bottom = (detection.bottom - detection.height * inset - _cropTop) / _cropHeight;

    if (right <= 0 || left >= 1 || bottom <= 0 || top >= 1) {
      return null;
    }

    final x1 = (left.clamp(0.0, 1.0) * _outputWidth).floor();
    final x2 = (right.clamp(0.0, 1.0) * _outputWidth).ceil();
    final y1 = (top.clamp(0.0, 1.0) * _outputHeight).floor();
    final y2 = (bottom.clamp(0.0, 1.0) * _outputHeight).ceil();
    if (x1 >= x2 || y1 >= y2) return null;

    final values = <double>[];
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        final value = _output[y * _outputWidth + x];
        if (value.isFinite && value > 0) values.add(value);
      }
    }
    if (values.isEmpty) return null;

    values.sort();
    final raw = values.length.isOdd
        ? values[values.length ~/ 2]
        : (values[values.length ~/ 2 - 1] + values[values.length ~/ 2]) / 2;
    final corrected = math.max(0.0, slope * raw + intercept);
    return DepthReading(raw, corrected);
  }

  void _prepare(CameraImage image, int rotation) {
    final w = image.width, h = image.height;
    final rotated = rotation == 90 || rotation == 270;
    final uprightW = rotated ? h : w;
    final uprightH = rotated ? w : h;
    final target = _width / _height;
    double cropX = 0, cropY = 0;
    double cropW = uprightW.toDouble(), cropH = uprightH.toDouble();
    if (uprightW / uprightH > target) {
      cropW = uprightH * target;
      cropX = (uprightW - cropW) / 2;
    } else {
      cropH = uprightW / target;
      cropY = (uprightH - cropH) / 2;
    }
    _cropLeft = cropX / uprightW;
    _cropTop = cropY / uprightH;
    _cropWidth = cropW / uprightW;
    _cropHeight = cropH / uprightH;
    final yp = image.planes[0], up = image.planes[1], vp = image.planes[2];
    final uStride = up.bytesPerPixel ?? 1;
    final vStride = vp.bytesPerPixel ?? 1;
    const means = [0.485, 0.456, 0.406];
    const stds = [0.229, 0.224, 0.225];
    final area = _width * _height;

    for (int j = 0; j < _height; j++) {
      final uy = math.min(uprightH - 1, (cropY + j * cropH / _height).floor());
      for (int i = 0; i < _width; i++) {
        final ux = math.min(uprightW - 1, (cropX + i * cropW / _width).floor());
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
        final luminance = yp.bytes[sy * yp.bytesPerRow + sx];
        final u = up.bytes[(sy >> 1) * up.bytesPerRow + (sx >> 1) * uStride] - 128;
        final v = vp.bytes[(sy >> 1) * vp.bytesPerRow + (sx >> 1) * vStride] - 128;
        double normalized(double value, int channel) =>
          ((value.clamp(0.0, 255.0) / 255) - means[channel]) / stds[channel];
        final index = j * _width + i;
        _input[index] = normalized(luminance + 1.402 * v, 0);
        _input[area + index] = normalized(luminance - 0.344136 * u - 0.714136 * v, 1);
        _input[2 * area + index] = normalized(luminance + 1.772 * u, 2);
      }
    }
  }

  void close() => _interpreter?.close();
}
