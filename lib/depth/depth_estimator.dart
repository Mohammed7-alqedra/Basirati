import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../detection/yolo_detector.dart';

/// Prototype monocular depth. Raw model output must be calibrated against
/// measured distances before it can be interpreted as reliable meters.
/// Do not use this for independent navigation or obstacle safety warnings.
class DepthEstimator {
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

  /// Median of central object area. Display only as uncalibrated estimate.
  double? metersFor(Detection detection) {
    if (!_hasDepth) return null;
    final l = (detection.left + detection.width * 0.25 - _cropLeft) / _cropWidth;
    final r = (detection.right - detection.width * 0.25 - _cropLeft) / _cropWidth;
    final t = (detection.top + detection.height * 0.25 - _cropTop) / _cropHeight;
    final b = (detection.bottom - detection.height * 0.25 - _cropTop) / _cropHeight;
    if (r <= 0 || l >= 1 || b <= 0 || t >= 1) return null;
    final x1 = (l.clamp(0.0, 1.0) * (_outputWidth - 1)).floor();
    final x2 = (r.clamp(0.0, 1.0) * (_outputWidth - 1)).ceil();
    final y1 = (t.clamp(0.0, 1.0) * (_outputHeight - 1)).floor();
    final y2 = (b.clamp(0.0, 1.0) * (_outputHeight - 1)).ceil();
    final values = <double>[];
    final span = math.max(1, (x2 - x1 + 1) * (y2 - y1 + 1));
    final step = math.max(1, math.sqrt(span / 1200).ceil());
    for (int y = y1; y <= y2; y += step) {
      for (int x = x1; x <= x2; x += step) {
        final value = _output[y * _outputWidth + x];
        if (value.isFinite && value > 0) values.add(value);
      }
    }
    if (values.isEmpty) return null;
    values.sort();
    return values[values.length ~/ 2];
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
