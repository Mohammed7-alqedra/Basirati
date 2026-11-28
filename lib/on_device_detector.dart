import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A detection computed on the Android phone. Boxes are upright-image
/// normalized coordinates, matching the normalized boxes sent to Colab.
class LocalDetection {
  const LocalDetection({
    required this.name,
    required this.score,
    required this.box,
    this.distanceMeters,
    this.distanceAt,
  });

  final String name;
  final double score;
  final Rect box;
  final double? distanceMeters;
  final DateTime? distanceAt;

  LocalDetection withDistance(double distance, DateTime timestamp) {
    return LocalDetection(
      name: name,
      score: score,
      box: box,
      distanceMeters: distance,
      distanceAt: timestamp,
    );
  }

  Map<String, dynamic> toDepthRequest() => {
        'label': name,
        'score': score,
        'left': box.left,
        'top': box.top,
        'right': box.right,
        'bottom': box.bottom,
      };

  String get overlayLabel {
    final distance = distanceMeters;
    if (distance == null) {
      return '$name — measuring…';
    }
    return '$name — ${distance.toStringAsFixed(2)} m';
  }

  bool get isNear {
    final d = distanceMeters;
    if (d == null) {
      return false;
    }
    const vehicles = <String>{
      'car', 'truck', 'bus', 'motorcycle', 'bicycle',
    };
    return d < (vehicles.contains(name.toLowerCase()) ? 3.0 : 1.2);
  }
}

double boxIoU(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) {
    return 0;
  }
  final union = a.width * a.height + b.width * b.height -
      intersection.width * intersection.height;
  return union > 0 ? intersection.width * intersection.height / union : 0;
}

/// Retain an estimate only while the same labeled object stays in a
/// sufficiently similar position. Avoid assigning one chair's distance
/// to another chair nearby.
List<LocalDetection> keepRecentDistances(
  List<LocalDetection> current,
  List<LocalDetection> previous,
  DateTime now, {
  Duration maxAge = const Duration(seconds: 8),
}) {
  final used = <int>{};
  return current.map((object) {
    int? best;
    var highestIoU = 0.25;
    for (var i = 0; i < previous.length; i++) {
      final candidate = previous[i];
      if (used.contains(i) || candidate.name != object.name ||
          candidate.distanceMeters == null ||
          candidate.distanceAt == null ||
          now.difference(candidate.distanceAt!) > maxAge) {
        continue;
      }
      final overlap = boxIoU(candidate.box, object.box);
      if (overlap > highestIoU) {
        highestIoU = overlap;
        best = i;
      }
    }
    if (best == null) {
      return object;
    }
    used.add(best);
    return object.withDistance(
      previous[best].distanceMeters!,
      previous[best].distanceAt!,
    );
  }).toList();
}

/// Apply Colab distances to currently visible phone detections.
/// Data is matched by label and overlap, never merely by class or list index.
List<LocalDetection> attachDepthResults(
  List<LocalDetection> current,
  List<LocalDetection> sent,
  Object? responseDetections,
  DateTime receivedAt,
) {
  if (responseDetections is! List) {
    return current;
  }
  final candidates = <({String name, Rect box, double distance})>[];
  for (final raw in responseDetections) {
    if (raw is! Map) {
      continue;
    }
    final name = raw['label'];
    final distance = raw['calibrated_distance_m'];
    final coords = [raw['left'], raw['top'], raw['right'], raw['bottom']];
    if (name is! String || distance is! num || !distance.isFinite ||
        distance < 0 || coords.any((e) => e is! num)) {
      continue;
    }
    final box = Rect.fromLTRB(
      (coords[0] as num).toDouble(),
      (coords[1] as num).toDouble(),
      (coords[2] as num).toDouble(),
      (coords[3] as num).toDouble(),
    );
    if (box.isEmpty) {
      continue;
    }
    candidates.add((name: name, box: box, distance: distance.toDouble()));
  }
  // Only accept Colab results whose normalized box matches one sent to it.
  final verified = candidates.where((result) => sent.any((item) =>
      item.name == result.name && boxIoU(item.box, result.box) > 0.95)).toList();
  final used = <int>{};
  return current.map((object) {
    int? best;
    var highestIoU = 0.25;
    for (var i = 0; i < verified.length; i++) {
      if (used.contains(i) || verified[i].name != object.name) {
        continue;
      }
      final overlap = boxIoU(verified[i].box, object.box);
      if (overlap > highestIoU) {
        highestIoU = overlap;
        best = i;
      }
    }
    if (best == null) {
      return object;
    }
    used.add(best);
    return object.withDistance(verified[best].distance, receivedAt);
  }).toList();
}

/// Parses the Ultralytics Flutter plugin's single-image 'boxes' result.
/// These bounding boxes are computed on-device, not by the Colab notebook.
List<LocalDetection> parseYoloBoxes(Object? results) {
  if (results is! List) {
    return const [];
  }
  final found = <LocalDetection>[];
  for (final raw in results) {
    if (raw is! Map) {
      continue;
    }
    final name = raw['class'];
    final confidence = raw['confidence'];
    final values = [
      raw['x1_norm'], raw['y1_norm'], raw['x2_norm'], raw['y2_norm'],
    ];
    if (name is! String || name.isEmpty || confidence is! num ||
        !confidence.isFinite || values.any((v) => v is! num)) {
      continue;
    }
    final left = (values[0] as num).toDouble().clamp(0.0, 1.0).toDouble();
    final top = (values[1] as num).toDouble().clamp(0.0, 1.0).toDouble();
    final right = (values[2] as num).toDouble().clamp(0.0, 1.0).toDouble();
    final bottom = (values[3] as num).toDouble().clamp(0.0, 1.0).toDouble();
    if (right <= left || bottom <= top) {
      continue;
    }
    found.add(LocalDetection(
      name: name,
      score: confidence.toDouble(),
      box: Rect.fromLTRB(left, top, right, bottom),
    ));
  }
  return found;
}

/// Object detection stays on Android; this downloads and caches the official
/// YOLO11 Nano model once. No camera image is sent to a YOLO server.
class OnDeviceObjectDetector {
  static const modelUrl =
      'https://github.com/ultralytics/yolo-flutter-app/releases/'
      'download/v0.2.0/yolo11n.tflite';

  final YOLO _model = YOLO(
    modelPath: modelUrl,
    task: YOLOTask.detect,
  );
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = await _model.loadModel();
    if (!_loaded) {
      throw StateError('Could not load YOLO11 Nano on this phone.');
    }
  }

  Future<List<LocalDetection>> detect(Uint8List jpeg) async {
    if (!_loaded) {
      throw StateError('On-device detector not loaded.');
    }
    final result = await _model.predict(jpeg, confidenceThreshold: 0.25);
    return parseYoloBoxes(result['boxes']);
  }

  Future<void> dispose() => _model.dispose();
}
