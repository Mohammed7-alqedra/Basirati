import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'colab_depth_client.dart';
import 'detection_overlay.dart';
import 'on_device_detector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasiratiApp());
}

class BasiratiApp extends StatelessWidget {
  const BasiratiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baseerte AI — Update 10',
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
  final _http = http.Client();
  final _detector = OnDeviceObjectDetector();

  CameraController? _camera;
  Timer? _sampleTimer;
  Timer? _staleTimer;
  String? _colabUrl;
  List<LocalDetection> _detections = const [];
  String? _visibilityWarning;
  String _status = 'YOLO11 runs on the phone; distances run in Colab.';
  bool _connecting = false;
  bool _capturing = false;
  bool _depthInFlight = false;
  int _session = 0;

  Future<void> _connect() async {
    if (_connecting || _camera != null) {
      return;
    }

    final entered = _urlController.text.trim()
        .replaceAll(RegExp(r'/+$'), '');
    final base = entered.isEmpty ? null : entered;
    if (base != null) {
      final uri = Uri.tryParse(base);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        setState(() => _status = 'Enter a valid HTTPS Colab URL, '
            'or leave it empty for object detection only.');
        return;
      }
    }

    setState(() {
      _connecting = true;
      _status = 'Loading YOLO11 Nano on the Android phone. '
          'First run downloads the model once…';
    });

    CameraController? newCamera;
    try {
      // This is ON-DEVICE YOLO inference, never a Colab YOLO request.
      await _detector.load();

      if (base != null) {
        setState(() => _status = 'Checking the Update 10 Colab depth API…');
        final response = await _http.get(Uri.parse('$base/health'))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw StateError('Colab /health returned HTTP '
              '${response.statusCode}');
        }
        final body = jsonDecode(response.body);
        if (body is! Map || body['depth_model'] == null ||
            body['yolo_in_colab'] != false) {
          throw StateError('This is not the Update 10 depth-only API. '
              'Run Maya Alsuos update 10.ipynb instead of Update 8.');
        }
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera available');
      }
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
      setState(() {
        _camera = newCamera;
        _colabUrl = base;
        _detections = const [];
        _visibilityWarning = null;
        _status = base == null
            ? 'Phone YOLO11 active. Offline object detection only.'
            : 'Phone YOLO11 active; Colab provides distances.';
      });
      _sampleTimer?.cancel();
      _sampleTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_samplePhonePhoto(session)),
      );
      unawaited(_samplePhonePhoto(session));
    } catch (error) {
      if (newCamera != null && !identical(newCamera, _camera)) {
        await newCamera.dispose();
      }
      if (mounted) {
        setState(() => _status = 'Connection error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _samplePhonePhoto(int session) async {
    final camera = _camera;
    if (_capturing || !mounted || session != _session ||
        camera == null || !camera.value.isInitialized ||
        camera.value.isTakingPicture) {
      return;
    }
    _capturing = true;
    try {
      // Keep the original still-photo capture. The exact same JPEG goes to
      // the phone's YOLO and Colab's depth API (no YUV conversion).
      final photo = await camera.takePicture();
      late final Uint8List jpeg;
      try {
        jpeg = await photo.readAsBytes();
      } finally {
        try {
          await File(photo.path).delete();
        } catch (_) {}
      }
      if (!mounted || session != _session) {
        return;
      }

      final fresh = await _detector.detect(jpeg);
      if (!mounted || session != _session) {
        return;
      }

      final now = DateTime.now();
      final updated = keepRecentDistances(fresh, _detections, now);
      _staleTimer?.cancel();
      setState(() {
        _detections = updated;
        _status = _colabUrl == null
            ? 'Phone YOLO11: ${fresh.length} objects (offline).'
            : 'Phone YOLO11: ${fresh.length} objects. '
              'Distance estimates update from Colab.';
      });

      // A failed or paused capture must not leave stale boxes forever.
      _staleTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted || session != _session) {
          return;
        }
        setState(() {
          _detections = const [];
          _status = 'No fresh phone camera detection; boxes hidden.';
        });
      });

      final url = _colabUrl;
      if (url != null && !_depthInFlight) {
        unawaited(_requestDepth(
          session: session,
          baseUrl: url,
          jpeg: jpeg,
          sent: fresh,
        ));
      }
    } catch (error) {
      if (mounted && session == _session) {
        setState(() => _status = 'On-device camera/YOLO error: $error');
      }
    } finally {
      _capturing = false;
    }
  }

  Future<void> _requestDepth({
    required int session,
    required String baseUrl,
    required Uint8List jpeg,
    required List<LocalDetection> sent,
  }) async {
    if (_depthInFlight) {
      return;
    }
    _depthInFlight = true;
    final started = DateTime.now();
    try {
      final result = await ColabDepthClient(_http).estimate(
        baseUrl: baseUrl,
        jpegBytes: jpeg,
        detections: sent,
      );
      if (!mounted || session != _session ||
          DateTime.now().difference(started) >
              const Duration(seconds: 8)) {
        return;
      }

      final now = DateTime.now();
      final enriched = attachDepthResults(
        _detections,
        sent,
        result['detections'],
        now,
      );
      final visibility = result['camera_visibility'];
      final warning = visibility is Map
          ? visibility['warning_message']?.toString()
          : null;

      setState(() {
        _detections = enriched;
        _visibilityWarning = warning;
      });
    } catch (error) {
      if (mounted && session == _session) {
        setState(() {
          _visibilityWarning = 'Depth server unavailable; '
              'YOLO object detection continues on the phone.';
        });
      }
    } finally {
      _depthInFlight = false;
    }
  }

  Future<void> _disconnect() async {
    ++_session;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    final previous = _camera;
    if (mounted) {
      setState(() {
        _camera = null;
        _colabUrl = null;
        _detections = const [];
        _visibilityWarning = null;
        _status = 'Disconnected. Ready to start again.';
      });
    }
    await previous?.dispose();
  }

  @override
  void dispose() {
    ++_session;
    _sampleTimer?.cancel();
    _staleTimer?.cancel();
    _http.close();
    _urlController.dispose();
    final camera = _camera;
    if (camera != null) {
      unawaited(camera.dispose());
    }
    unawaited(_detector.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Baseerte AI — Update 10')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (camera == null) ...[
                const Text(
                  'Run "Maya Alsuos update 10.ipynb" in Google Colab '
                  'and paste its HTTPS API URL. Leave blank to use '
                  'offline YOLO object detection without distances.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Update 10 Colab depth URL (optional)',
                    hintText: 'https://example.trycloudflare.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: Text(_connecting
                      ? 'Starting…' : 'Start camera'),
                ),
                const SizedBox(height: 8),
                const Text('First launch downloads the YOLO11 Nano '
                    'TFLite model. After that YOLO runs on the phone.'),
              ] else ...[
                Expanded(
                  child: LiveCameraWithDetections(
                    preview: CameraPreview(camera),
                    previewAspectRatio:
                        MediaQuery.orientationOf(context) ==
                                Orientation.portrait
                            ? 1 / camera.value.aspectRatio
                            : camera.value.aspectRatio,
                    detections: _detections,
                  ),
                ),
                const SizedBox(height: 8),
                if (_visibilityWarning != null)
                  Text(
                    _visibilityWarning!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                OutlinedButton(
                  onPressed: _disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 4),
              const Text(
                'YOLO detections run locally. Photos and object boxes are '
                'sent to Colab only when a depth URL is connected. '
                'Distance and near-object flags are experimental; '
                'do not use for safe navigation.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
