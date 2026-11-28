import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../detection/yolo_detector.dart';

/// A distance returned by Update 10 Colab for an object found by local YOLO.
class DepthEstimate {
  const DepthEstimate({
    required this.label,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.meters,
    required this.measuredAt,
  });

  final String label;
  final double left, top, right, bottom;
  final double meters;
  final DateTime measuredAt;
}

/// Pure geometry association: a distance belongs only to an overlapping box
/// with the same class label, not every object of that class.
double detectionOverlap(Detection d, DepthEstimate e) {
  final left = d.left > e.left ? d.left : e.left;
  final top = d.top > e.top ? d.top : e.top;
  final right = d.right < e.right ? d.right : e.right;
  final bottom = d.bottom < e.bottom ? d.bottom : e.bottom;
  final w = right - left;
  final h = bottom - top;
  if (w <= 0 || h <= 0) {
    return 0;
  }
  final inter = w * h;
  final da = d.width * d.height;
  final ea = (e.right - e.left) * (e.bottom - e.top);
  final union = da + ea - inter;
  return union > 0 ? inter / union : 0;
}

DepthEstimate? estimateForObject(
  Detection detection,
  List<DepthEstimate> estimates,
  DateTime now, {
  Duration maxAge = const Duration(seconds: 6),
}) {
  DepthEstimate? best;
  var maxOverlap = 0.3;
  for (final estimate in estimates) {
    if (estimate.label != detection.label ||
        now.difference(estimate.measuredAt) > maxAge) {
      continue;
    }
    final overlap = detectionOverlap(detection, estimate);
    if (overlap > maxOverlap) {
      maxOverlap = overlap;
      best = estimate;
    }
  }
  return best;
}

/// Send the same camera frame as the on-phone detector, plus its normalized
/// boxes. No YOLO model runs in this client or on Colab.
class ColabDepthClient {
  ColabDepthClient(this._http);

  final http.Client _http;

  Future<void> checkHealth(String baseUrl) async {
    final response = await _http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Depth server returned HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['depth_model'] == null ||
        data['yolo_in_colab'] != false) {
      throw StateError('Not an Update 10 depth-only Colab server.');
    }
  }

  Future<List<DepthEstimate>> estimate({
    required String baseUrl,
    required Uint8List jpeg,
    required List<Detection> detections,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/estimate-depth'),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      jpeg,
      filename: 'frame.jpg',
    ));
    request.fields['detections'] = jsonEncode([
      for (final detection in detections)
        <String, dynamic>{
          'classId': detection.classId,
          'label': detection.label,
          'score': detection.score,
          'left': detection.left.clamp(0.0, 1.0),
          'top': detection.top.clamp(0.0, 1.0),
          'right': detection.right.clamp(0.0, 1.0),
          'bottom': detection.bottom.clamp(0.0, 1.0),
          'isObstacle': detection.isObstacle,
        },
    ]);
    final stream = await _http.send(request).timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(stream)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('Depth request failed: HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map || payload['detections'] is! List) {
      throw const FormatException('Invalid distance response from Colab');
    }
    return parseDepthEstimates(payload['detections'], DateTime.now());
  }
}

List<DepthEstimate> parseDepthEstimates(Object? values, DateTime measuredAt) {
  if (values is! List) {
    return const [];
  }
  final estimates = <DepthEstimate>[];
  for (final item in values) {
    if (item is! Map) {
      continue;
    }
    final fields = [
      item['left'], item['top'], item['right'], item['bottom'],
    ];
    final distance = item['calibrated_distance_m'];
    if (item['label'] is! String || distance is! num ||
        !distance.isFinite || distance < 0 ||
        fields.any((value) => value is! num)) {
      continue;
    }
    final x1 = (fields[0] as num).toDouble();
    final y1 = (fields[1] as num).toDouble();
    final x2 = (fields[2] as num).toDouble();
    final y2 = (fields[3] as num).toDouble();
    if (![x1, y1, x2, y2].every((v) => v.isFinite) ||
        x1 < 0 || y1 < 0 || x2 > 1 || y2 > 1 ||
        x2 <= x1 || y2 <= y1) {
      continue;
    }
    estimates.add(DepthEstimate(
      label: item['label'] as String,
      left: x1,
      top: y1,
      right: x2,
      bottom: y2,
      meters: distance.toDouble(),
      measuredAt: measuredAt,
    ));
  }
  return estimates;
}
