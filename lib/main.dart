import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'detection_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasiratiApp());
}

/// Camera client for Maya Alsuos update 8.ipynb (YOLOv5nu + Depth Anything V2).
/// No AI model is executed on the Android device.
class BasiratiApp extends StatelessWidget {
  const BasiratiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basirati AI - Maya Update 8',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const NotebookCameraScreen(),
    );
  }
}

class NotebookCameraScreen extends StatefulWidget {
  const NotebookCameraScreen({super.key});

  @override
  State<NotebookCameraScreen> createState() => _NotebookCameraScreenState();
}

class _NotebookCameraScreenState extends State<NotebookCameraScreen> {
  final _urlController = TextEditingController();
  final _client = http.Client();

  CameraController? _camera;
  Timer? _timer;
  List<ObjectDetection> _detections = const [];
  Size? _photoSize;
  Timer? _boxExpiry;
  String? _visibilityWarning;
  bool _dangerAlert = false;
  String? _baseUrl;
  String _status = 'Run Maya Alsuos update 8.ipynb and paste its HTTPS API URL.';
  bool _connecting = false;
  bool _processing = false;
  int _session = 0;

  Future<void> _connect() async {
    if (_connecting || _camera != null) return;

    final base = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _status = 'Enter a valid HTTPS notebook URL.');
      return;
    }

    setState(() {
      _connecting = true;
      _status = 'Connecting to notebook...';
    });

    CameraController? newCamera;
    try {
      final response = await _client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('API health check returned ${response.statusCode}');
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera available');
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      newCamera = CameraController(
        rear,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await newCamera.initialize();
      if (!mounted) {
        await newCamera.dispose();
        return;
      }

      final session = ++_session;
      _boxExpiry?.cancel();
      setState(() {
        _camera = newCamera;
        _baseUrl = base;
        _detections = const [];
        _photoSize = null;
        _visibilityWarning = null;
        _dangerAlert = false;
        _status = 'Connected to Maya Update 8 model server.';
      });

      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_sendFrame(session)),
      );
      unawaited(_sendFrame(session));
    } catch (error) {
      if (newCamera != null && !identical(newCamera, _camera)) {
        await newCamera.dispose();
      }
      if (mounted) setState(() => _status = 'Connection error: $error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _sendFrame(int session) async {
    final camera = _camera;
    final base = _baseUrl;
    if (_processing || !mounted || session != _session ||
        camera == null || base == null ||
        !camera.value.isInitialized || camera.value.isTakingPicture) {
      return;
    }

    _processing = true;
    try {
      final photo = await camera.takePicture();
      final capturedAt = DateTime.now();
      late final Uint8List bytes;
      try {
        bytes = await photo.readAsBytes();
      } finally {
        try {
          await File(photo.path).delete();
        } catch (_) {}
      }
      if (!mounted || session != _session) return;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$base/process-frame'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'camera.jpg',
      ));

      final streamed = await _client.send(request)
          .timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        throw StateError('API returned HTTP ${response.statusCode}');
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (result['status'] == 'dropped') return;
      if (result['status'] != 'processed') {
        throw StateError('Unexpected notebook API response');
      }

      // Read dimensions from the existing annotated JPEG header. The full
      // JPEG is never decoded or displayed over the live camera.
      final jpeg = result['output_frame'];
      final photoSize = jpeg is String ? jpegSizeFromBase64(jpeg) : null;
      final detections = detectionsFromApi(result['detections']);
      // Retain the latest detection between successful photo requests,
      // rather than clearing it after 3 seconds. The safety watchdog still
      // hides boxes if the AI stops returning fresh snapshots.
      const maxBoxAge = Duration(seconds: 12);
      final age = DateTime.now().difference(capturedAt);
      final showBoxes = photoSize != null &&
          age < maxBoxAge && age >= Duration.zero;

      final visibility = result['camera_visibility'];
      final warning = visibility is Map
          ? visibility['warning_message']?.toString()
          : null;
      final danger = result['trigger_vibration'] == true;

      if (!mounted || session != _session) return;

      _boxExpiry?.cancel();
      setState(() {
        _detections = showBoxes ? detections : const [];
        _photoSize = showBoxes ? photoSize : null;
        _visibilityWarning = warning;
        _dangerAlert = danger && showBoxes;
        final seconds = result['processing_time'];
        final timing = seconds is num
            ? ' in ${seconds.toStringAsFixed(2)} s'
            : '';
        _status = !showBoxes
            ? 'AI result too old or image dimensions unavailable. '
              'No boxes shown; keep the camera steady.'
            : detections.isEmpty
                ? 'No objects detected in the latest AI snapshot.'
                : 'AI snapshot$timing. Distance is experimental.';
      });
      if (showBoxes && detections.isNotEmpty) {
        _boxExpiry = Timer(maxBoxAge - age, () {
          if (!mounted || session != _session) return;
          setState(() {
            _detections = const [];
            _photoSize = null;
            _dangerAlert = false;
            _status = 'No fresh AI update for 12 seconds. '
                'Boxes hidden until another detection arrives.';
          });
        });
      }
    } catch (error) {
      if (mounted && session == _session) {
        setState(() => _status = 'Frame error: $error');
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _disconnect() async {
    ++_session;
    _timer?.cancel();
    _timer = null;
    _boxExpiry?.cancel();
    _boxExpiry = null;
    final previous = _camera;
    if (mounted) {
      setState(() {
        _camera = null;
        _baseUrl = null;
        _detections = const [];
        _photoSize = null;
        _visibilityWarning = null;
        _dangerAlert = false;
        _status = 'Disconnected. Reconnect with the current API URL.';
      });
    }
    await previous?.dispose();
  }

  @override
  void dispose() {
    ++_session;
    _timer?.cancel();
    _boxExpiry?.cancel();
    _client.close();
    _urlController.dispose();
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Basirati AI - Maya Update 8')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (camera == null) ...[
                const Text('Run Maya Alsuos update 8.ipynb in Colab. '
                    'Copy the API PUBLIC URL from the last cell.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Notebook server URL',
                    hintText: 'https://example.trycloudflare.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: Text(_connecting
                      ? 'Connecting...' : 'Connect to notebook'),
                ),
              ] else ...[
                Expanded(
                  flex: 3,
                  child: LiveCameraWithDetections(
                    preview: CameraPreview(camera),
                    previewAspectRatio:
                        MediaQuery.orientationOf(context) == Orientation.portrait
                            ? 1 / camera.value.aspectRatio
                            : camera.value.aspectRatio,
                    detections: _detections,
                    photoSize: _photoSize,
                    sensorOrientation: camera.description.sensorOrientation,
                  ),
                ),
                const SizedBox(height: 8),
                if (_visibilityWarning != null)
                  Text(_visibilityWarning!, style: const TextStyle(color: Colors.orangeAccent)),
                if (_dangerAlert)
                  const Text('Nearby object alert (experimental)',
                      style: TextStyle(color: Colors.redAccent)),
                OutlinedButton(
                  onPressed: _disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 4),
              const Text(
                'Photos are uploaded to the notebook server. '
                'Boxes come from the last photo and can lag behind motion. '
                'Do not use experimental distances for safe navigation.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

