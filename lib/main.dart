import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'camera_frame_encoder.dart';
import 'detection_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the frame rotation and on-screen bounding boxes in the same
  // orientation. Landscape support requires a separate rotation mapping.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BasiratiApp());
}

/// Android is a camera-and-network client; all Maya AI inference stays in the
/// notebook (YOLOv5 Nano + Depth Anything V2).
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
  static const Duration _minRequestInterval = Duration(milliseconds: 500);
  static const Duration _overlayLifetime = Duration(seconds: 2);

  final _urlController = TextEditingController();
  final _client = http.Client();

  CameraController? _camera;
  String? _baseUrl;
  List<DetectionOverlayItem> _detections = const [];
  List<String> _objects = const [];
  List<String> _announcements = const [];
  String? _visibilityWarning;
  bool _dangerAlert = false;
  int _imageWidth = 0;
  int _imageHeight = 0;
  String _status = 'Run Maya Alsuos update 8.ipynb and paste its HTTPS URL.';
  bool _connecting = false;
  bool _processing = false;
  int _session = 0;
  DateTime? _lastRequestAt;
  Timer? _overlayExpiry;

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
      _status = 'Connecting to the notebook API...';
    });

    CameraController? newCamera;
    try {
      final health = await _client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 12));
      if (health.statusCode != 200) {
        throw StateError('API health check returned ${health.statusCode}');
      }

      final cameras = await availableCameras();
      final rear = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (rear.isEmpty) throw StateError('Rear camera is not available');

      newCamera = CameraController(
        rear.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await newCamera.initialize();
      await newCamera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await newCamera.dispose();
        return;
      }

      final session = ++_session;
      _processing = false;
      _lastRequestAt = null;
      _overlayExpiry?.cancel();
      setState(() {
        _camera = newCamera;
        _baseUrl = base;
        _detections = const [];
        _objects = const [];
        _announcements = const [];
        _visibilityWarning = null;
        _dangerAlert = false;
        _imageWidth = 0;
        _imageHeight = 0;
        _status = 'Live camera started. Waiting for AI detections...';
      });

      await newCamera.startImageStream(
        (image) => _onCameraFrame(image, session),
      );
    } catch (error) {
      if (newCamera != null) {
        try {
          if (newCamera.value.isStreamingImages) {
            await newCamera.stopImageStream();
          }
          await newCamera.dispose();
        } catch (_) {
          // Keep the original connection error visible.
        }
      }
      if (mounted) {
        setState(() {
          _camera = null;
          _baseUrl = null;
          _status = 'Connection error: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _onCameraFrame(CameraImage image, int session) {
    final camera = _camera;
    if (!mounted ||
        session != _session ||
        _processing ||
        camera == null ||
        _baseUrl == null ||
        !camera.value.isInitialized) {
      return;
    }

    final now = DateTime.now();
    if (_lastRequestAt != null &&
        now.difference(_lastRequestAt!) < _minRequestInterval) {
      return;
    }

    // Only copy an occasional frame; all other frames are discarded.
    _processing = true;
    _lastRequestAt = now;
    try {
      final format = switch (image.format.group) {
        ImageFormatGroup.yuv420 => FramePixelFormat.yuv420,
        ImageFormatGroup.nv21 => FramePixelFormat.nv21,
        ImageFormatGroup.bgra8888 => FramePixelFormat.bgra8888,
        _ => throw UnsupportedError(
            'Unsupported camera image format: ${image.format.group}',
          ),
      };
      final snapshot = CameraFrameSnapshot(
        width: image.width,
        height: image.height,
        rotationDegrees: Platform.isAndroid
            ? camera.description.sensorOrientation
            : 0,
        pixelFormat: format,
        planes: image.planes.map((plane) {
          return FramePlaneSnapshot(
            Uint8List.fromList(plane.bytes),
            plane.bytesPerRow,
            plane.bytesPerPixel ?? 1,
          );
        }).toList(growable: false),
      );
      unawaited(_sendCameraFrame(snapshot, session));
    } catch (error) {
      _processing = false;
      setState(() => _status = 'Camera frame error: $error');
    }
  }

  Future<void> _sendCameraFrame(
    CameraFrameSnapshot snapshot,
    int session,
  ) async {
    final timer = Stopwatch()..start();
    try {
      // CPU-heavy conversion and JPEG compression are NOT run on the UI isolate.
      final frame = await encodeCameraFrameAsync(snapshot);
      final base = _baseUrl;
      if (!mounted || session != _session || base == null) return;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$base/process-frame'),
      );
      // New notebook API mode: only JSON metadata, no base64 image.
      request.fields['include_image'] = 'false';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        frame.jpeg,
        filename: 'camera.jpg',
      ));

      final streamed = await _client.send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('Notebook API returned ${response.statusCode}');
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (result['status'] == 'dropped') return;
      if (result['status'] != 'processed') {
        throw StateError('Unexpected notebook API response');
      }
      if (!mounted || session != _session) return;

      final width = (result['frame_width'] as num?)?.toInt() ?? frame.width;
      final height = (result['frame_height'] as num?)?.toInt() ?? frame.height;
      final overlay = <DetectionOverlayItem>[];
      final objects = <String>[];
      final entries = result['detections'];
      if (entries is List && width > 0 && height > 0) {
        for (final entry in entries) {
          if (entry is! Map) continue;
          final label = entry['object']?.toString() ?? 'object';
          final distance = entry['calibrated_distance_m'];
          final meters = distance is num ? distance.toDouble() : null;
          final dangerous = entry['danger_zone'] == true;
          final proximity = entry['proximity_level']?.toString() ?? '';
          objects.add(
            '${dangerous ? "[NEAR] " : ""}$label - '
            '${meters == null ? "unknown distance" : "${meters.toStringAsFixed(2)} m (test)"}'
            '${proximity.isEmpty ? "" : " - $proximity"}',
          );

          final bbox = entry['bbox'];
          if (bbox is! List || bbox.length != 4 ||
              bbox.any((coordinate) => coordinate is! num)) {
            continue;
          }
          final left = (bbox[0] as num).toDouble();
          final top = (bbox[1] as num).toDouble();
          final right = (bbox[2] as num).toDouble();
          final bottom = (bbox[3] as num).toDouble();
          if (right <= left || bottom <= top) continue;
          overlay.add(DetectionOverlayItem(
            bounds: Rect.fromLTRB(
              left / width, top / height, right / width, bottom / height,
            ),
            label: label,
            distanceMeters: meters,
            danger: dangerous,
          ));
        }
      }

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
      final serverSeconds = result['processing_time'];
      final serverTime = serverSeconds is num
          ? '${serverSeconds.toStringAsFixed(2)}s'
          : '?';

      timer.stop();
      setState(() {
        _detections = overlay;
        _objects = objects;
        _announcements = announcements;
        _visibilityWarning = warning;
        _dangerAlert = result['trigger_vibration'] == true;
        _imageWidth = width;
        _imageHeight = height;
        _status = 'Live preview | AI: $serverTime | '
            'Capture + network + AI: ${timer.elapsedMilliseconds}ms';
      });

      // Never leave an old box over a new camera scene indefinitely.
      _overlayExpiry?.cancel();
      _overlayExpiry = Timer(_overlayLifetime, () {
        if (!mounted || session != _session) return;
        setState(() {
          _detections = const [];
          _objects = const [];
          _dangerAlert = false;
        });
      });
    } catch (error) {
      if (mounted && session == _session) {
        setState(() => _status = 'Frame processing error: $error');
      }
    } finally {
      if (session == _session) _processing = false;
    }
  }

  Future<void> _disconnect() async {
    ++_session;
    _overlayExpiry?.cancel();
    _overlayExpiry = null;
    final previous = _camera;
    _processing = false;
    _lastRequestAt = null;
    if (mounted) {
      setState(() {
        _camera = null;
        _baseUrl = null;
        _detections = const [];
        _objects = const [];
        _announcements = const [];
        _visibilityWarning = null;
        _dangerAlert = false;
        _imageWidth = 0;
        _imageHeight = 0;
        _status = 'Disconnected. Use the current notebook HTTPS URL.';
      });
    }
    if (previous != null) {
      try {
        if (previous.value.isStreamingImages) {
          await previous.stopImageStream();
        }
        await previous.dispose();
      } catch (_) {
        // A disconnected stream can throw during camera teardown.
      }
    }
  }

  @override
  void dispose() {
    ++_session;
    _overlayExpiry?.cancel();
    _client.close();
    _urlController.dispose();
    final previous = _camera;
    if (previous != null) {
      unawaited(() async {
        try {
          if (previous.value.isStreamingImages) {
            await previous.stopImageStream();
          }
          await previous.dispose();
        } catch (_) {}
      }());
    }
    super.dispose();
  }

  Widget _liveCamera(CameraController camera) {
    final preview = camera.value.previewSize;
    if (preview == null) return CameraPreview(camera);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The camera never gets replaced by an AI-generated still image.
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: preview.height,
              height: preview.width,
              child: CameraPreview(camera),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: DetectionPainter(
                detections: _detections,
                imageWidth: _imageWidth,
                imageHeight: _imageHeight,
              ),
            ),
          ),
          const Positioned(
            top: 10,
            left: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0x99000000)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('LIVE CAMERA', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Basirati AI - Maya Update 8')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                  child: Text(_connecting ? 'Connecting...' : 'Connect to notebook'),
                ),
              ] else ...[
                Expanded(flex: 3, child: _liveCamera(camera)),
                const SizedBox(height: 8),
                if (_visibilityWarning != null)
                  Text(_visibilityWarning!,
                      style: const TextStyle(color: Colors.orangeAccent)),
                if (_dangerAlert)
                  const Text('Nearby object alert (experimental)',
                      style: TextStyle(color: Colors.redAccent)),
                if (_announcements.isNotEmpty)
                  Text('Latest announcement: ${_announcements.join("; ")}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
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
                'Frames are uploaded to the notebook API. '
                'Distance and danger estimates are experimental; '
                'do not rely on them for navigation safety.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
