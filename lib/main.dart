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

/// Camera client for the Python API in Maya alsuos.ipynb.
/// No AI model is executed on the Android device.
class BasiratiApp extends StatelessWidget {
  const BasiratiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basirati notebook AI',
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
  Uint8List? _annotatedFrame;
  List<String> _objects = <String>[];
  String? _baseUrl;
  String _status = 'Run the Colab notebook and paste its public HTTPS URL.';
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
          .get(Uri.parse(base + '/health'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('API health check returned ' +
            response.statusCode.toString());
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
        _annotatedFrame = null;
        _objects = <String>[];
        _status = 'Connected to the notebook model server.';
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
      if (mounted) setState(() => _status = 'Connection error: ' + error.toString());
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
        Uri.parse(base + '/process-frame'),
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
        throw StateError('API returned HTTP ' + response.statusCode.toString());
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
              ? value.toStringAsFixed(2) + ' m (test)'
              : 'distance unavailable';
          objects.add(name + ' - ' + distance);
        }
      }

      final jpg = result['output_frame'];
      final annotated = jpg is String ? base64Decode(jpg) : null;
      if (!mounted || session != _session) return;

      setState(() {
        _objects = objects;
        _annotatedFrame = annotated;
        final seconds = result['processing_time'];
        _status = 'Notebook processed frame' +
            (seconds is num ? ' in ' + seconds.toStringAsFixed(2) + ' s' : '') +
            '. Distance is experimental.';
      });
    } catch (error) {
      if (mounted && session == _session) {
        setState(() => _status = 'Frame error: ' + error.toString());
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
        _annotatedFrame = null;
        _objects = <String>[];
        _status = 'Disconnected. Reconnect with the current Colab URL.';
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
      appBar: AppBar(title: const Text('Basirati notebook AI')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (camera == null) ...[
                const Text('Run Maya alsuos.ipynb in Colab. '
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
                  child: Center(
                    child: _annotatedFrame != null
                        ? Image.memory(
                            _annotatedFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : CameraPreview(camera),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Notebook detections:',
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
