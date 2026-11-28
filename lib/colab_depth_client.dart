import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'on_device_detector.dart';

/// Transport only. The Google Colab Update 10 notebook performs ALL depth
/// inference and distance calibration. No YOLO is run on the server.
class ColabDepthClient {
  const ColabDepthClient(this.httpClient);

  final http.Client httpClient;

  Future<Map<String, dynamic>> estimate({
    required String baseUrl,
    required Uint8List jpegBytes,
    required List<LocalDetection> detections,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/estimate-depth'),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      jpegBytes,
      filename: 'camera.jpg',
    ));
    request.fields['detections'] = jsonEncode(
      detections.map((item) => item.toDepthRequest()).toList(),
    );

    final stream = await httpClient.send(request)
        .timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(stream)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('Colab returned HTTP ${response.statusCode}: '
          '${response.body.length > 180 ? response.body.substring(0, 180) : response.body}');
    }
    final result = jsonDecode(response.body);
    if (result is! Map<String, dynamic> ||
        result['detections'] is! List) {
      throw const FormatException('Unexpected Update 10 depth API response.');
    }
    return result;
  }
}
