import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  List<String> _objects = <String>[];
  List<String> _announcements = <String>[];
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
      setState(() {
        _camera = newCamera;
        _baseUrl = base;
        _objects = <String>[];
        _announcements = <String>[];
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

      final objects = <String>[];
      final detections = result['detections'];
      if (detections is List) {
        for (final entry in detections) {
          if (entry is! Map) continue;
          final name = entry['object']?.toString() ?? 'object';
          final value = entry['calibrated_distance_m'];
          final distance = value is num
              ? '${value.toStringAsFixed(2)} m (test)'
              : 'distance unavailable';
          final proximity = entry['proximity_level']?.toString();
          final danger = entry['danger_zone'] == true;
          final tag = proximity == null ? '' : ' - $proximity';
          objects.add('${danger ? '[NEAR] ' : ''}$name - $distance$tag');
        }
      }

      // Update 8 includes visual warning/announcement data in its JSON API.
      // These are displayed only; the phone does not automatically vibrate
      // or speak based on unvalidated distance estimates.
      final announcements = <String>[];
      final newAnnouncements = result['announcements'];
      if (newAnnouncements is List) {
        for (final item in newAnnouncements) {
          if (item is Map && item['speech_text'] is String) {
            announcements.add(item['speech_text'] as String);
          }
        }
      }
      final visibility = result['camera_visibility'];
      final warning = visibility is Map
          ? visibility['warning_message']?.toString()
          : null;
      final danger = result['trigger_vibration'] == true;

      if (!mounted || session != _session) return;

      setState(() {
        _objects = objects;
        _announcements = announcements;
        _visibilityWarning = warning;
        _dangerAlert = danger;
        final seconds = result['processing_time'];
        final timing = seconds is num
            ? ' in ${seconds.toStringAsFixed(2)} s'
            : '';
        _status = 'Notebook processed frame$timing. '
            'Distance is experimental.';
      });
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
    final previous = _camera;
    if (mounted) {
      setState(() {
        _camera = null;
        _baseUrl = null;
        _objects = <String>[];
        _announcements = <String>[];
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
                    objects: _objects,
                  ),
                ),
                const SizedBox(height: 8),
                if (_visibilityWarning != null)
                  Text(_visibilityWarning!, style: const TextStyle(color: Colors.orangeAccent)),
                if (_dangerAlert)
                  const Text('Nearby object alert (experimental)',
                      style: TextStyle(color: Colors.redAccent)),
                if (_announcements.isNotEmpty)
                  Text('Latest announcement: ${_announcements.join("; ")}'),
                Text('Object detections and proximity:',
                    style: Theme.of(context).textTheme.titleMedium),
                Expanded(
                  child: ListView(
                    children: _objects.isEmpty
                        ? [const Text('No objects reported yet')]
                        : _objects.map((name) => Text(name)).toList(),
                  ),
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
                'Photos are uploaded to the notebook server. '
                'Warning flags are visual only in this version. '
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


/// Displays the real camera continuously, alongside the latest AI results.
/// AI detections may update slower than the live camera preview.
class LiveCameraWithDetections extends StatelessWidget {
  const LiveCameraWithDetections({
    super.key,
    required this.preview,
    required this.objects,
  });

  final Widget preview;
  final List<String> objects;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: preview),
        if (objects.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Latest AI snapshot (experimental)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      for (final object in objects.take(3))
                        Text(
                          object,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      if (objects.length > 3)
                        Text(
                          '+${objects.length - 3} more objects below',
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
