import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'detection/yolo_detector.dart';
import 'depth/colab_depth_client.dart';
import 'depth/frame_encoder.dart';
import 'ui/overlay_painter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BasiratiApp());
}

class BasiratiApp extends StatelessWidget {
  const BasiratiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Basirati AI',
      debugShowCheckedModeBanner: false,
      home: DetectionScreen(),
    );
  }
}

/// Adopted from basirati_for_det: local YOLO11 on the camera stream,
/// voice controls, and object overlays. Only depth estimation uses Colab.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  static const _keys = MethodChannel('basirati/keys');
  static const _preferenceKey = 'update10_colab_depth_url';

  final _detector = YoloDetector();
  final _tts = FlutterTts();
  final _http = http.Client();
  late final ColabDepthClient _depthClient = ColabDepthClient(_http);

  CameraController? _controller;
  List<Detection> _results = const [];
  List<DepthEstimate> _distances = const [];
  bool _busy = false;
  bool _uploading = false;
  bool _modelReady = false;
  int _session = 0;
  DateTime _lastUpload = DateTime.fromMillisecondsSinceEpoch(0);
  String _status = 'Starting camera…';
  String? _colabUrl;
  String? _colabWarning;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    _keys.setMethodCallHandler(_onKey);
    unawaited(_start());
    unawaited(_restoreColabUrl());
  }

  Future<void> _restoreColabUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_preferenceKey);
      if (saved == null || saved.isEmpty || !mounted) return;
      await _applyColabUrl(saved, save: false);
    } catch (error) {
      if (mounted) {
        setState(() => _colabWarning = 'Colab URL not restored: $error');
      }
    }
  }

  Future<void> _start() async {
    CameraController? pending;
    try {
      await _detector.load();
      _modelReady = true;
      await _tts.setLanguage('en-US');
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera found');
      }
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      pending = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await pending.initialize();
      if (!mounted) {
        await pending.dispose();
        return;
      }
      setState(() {
        _controller = pending;
        _status = 'Phone YOLO11 started. Local detection active.';
      });
      await pending.startImageStream(_onFrame);
      unawaited(_speak('Started'));
    } catch (error) {
      if (pending != null && !identical(pending, _controller)) {
        await pending.dispose();
      }
      if (mounted) setState(() => _status = 'Camera/YOLO error: $error');
    }
  }

  void _onFrame(CameraImage image) {
    final camera = _controller;
    if (_busy || camera == null || !mounted) return;
    _busy = true;
    final start = DateTime.now();
    try {
      // This detector is from the uploaded ZIP, not Ultralytics' other plugin.
      final results = _detector.detect(
        image,
        camera.description.sensorOrientation,
      );
      final durationMs = DateTime.now().difference(start).inMilliseconds;
      if (!mounted) return;
      setState(() {
        _results = results;
        _status = '${results.length} objects · $durationMs ms per YOLO frame'
            ' · ${_colabUrl == null ? 'Colab not connected' : 'Colab connected'}';
      });

      final url = _colabUrl;
      final now = DateTime.now();
      if (url != null && results.isNotEmpty && !_uploading &&
          now.difference(_lastUpload) >= const Duration(milliseconds: 1800)) {
        _uploading = true;
        _lastUpload = now;
        final session = _session;
        // jpegFromCameraFrame copies all planes synchronously, then encodes
        // in a worker isolate. It never calls takePicture during streaming.
        unawaited(_requestDistances(
          image,
          camera.description.sensorOrientation,
          List<Detection>.unmodifiable(results),
          url,
          session,
          now,
        ));
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'YOLO detection error: $error');
    } finally {
      _busy = false;
    }
  }

  Future<void> _requestDistances(
    CameraImage frame,
    int rotation,
    List<Detection> sent,
    String baseUrl,
    int session,
    DateTime capturedAt,
  ) async {
    try {
      final jpeg = await jpegFromCameraFrame(frame, rotation);
      if (!mounted || session != _session || _colabUrl != baseUrl) return;
      final distances = await _depthClient.estimate(
        baseUrl: baseUrl,
        jpeg: jpeg,
        detections: sent,
      );
      if (!mounted || session != _session || _colabUrl != baseUrl) return;
      // Don't apply old measurements to a live, moving camera picture.
      if (DateTime.now().difference(capturedAt) >
          const Duration(seconds: 6)) {
        return;
      }
      setState(() {
        _distances = distances;
        _colabWarning = null;
      });
    } catch (error) {
      if (mounted && session == _session && _colabUrl == baseUrl) {
        setState(() => _colabWarning = 'Distance server: $error');
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> _applyColabUrl(String value, {bool save = true}) async {
    final url = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (url.isEmpty) {
      ++_session;
      if (mounted) {
        setState(() {
          _colabUrl = null;
          _colabWarning = null;
          _distances = const [];
        });
      }
      if (save) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_preferenceKey);
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.path != '') {
      throw const FormatException('Paste only the HTTPS base URL from Colab.');
    }
    await _depthClient.checkHealth(url);
    if (!mounted) return;
    ++_session;
    setState(() {
      _colabUrl = url;
      _colabWarning = null;
      _distances = const [];
    });
    if (save) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, url);
    }
  }

  Future<void> _showColabSettings() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ColabSettingsDialog(
        initialUrl: _colabUrl ?? '',
        applyUrl: _applyColabUrl,
      ),
    );
  }

  Future<void> _onKey(MethodCall call) async {
    if (call.method == 'volumeUpLong') {
      _describeObjects();
    } else if (call.method == 'volumeUpShort') {
      unawaited(_speak('Room number reading is not ready yet'));
    }
  }

  /// Original ZIP voice feature, enhanced with distances when Colab returns.
  void _describeObjects() {
    final results = _results;
    if (results.isEmpty) {
      unawaited(_speak("I don't see any objects"));
      return;
    }
    final groups = <String, int>{};
    for (final d in results) {
      final estimate = estimateForObject(d, _distances, DateTime.now());
      final meters = estimate == null ? '' :
          ', about ${estimate.meters.toStringAsFixed(1)} meters';
      final key = '${d.label}|${d.direction}$meters';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    final phrases = groups.entries.map((entry) {
      final parts = entry.key.split('|');
      final label = parts[0];
      final directionAndDistance = parts[1];
      final plural = label == 'person' ? 'people' : '${label}s';
      final name = entry.value > 1 ? '${entry.value} $plural' : label;
      final where = directionAndDistance.startsWith('left')
          ? 'on your left'
          : directionAndDistance.startsWith('right')
              ? 'on your right'
              : 'ahead';
      final comma = directionAndDistance.indexOf(',');
      final distance = comma >= 0 ? directionAndDistance.substring(comma) : '';
      return '$name $where$distance';
    });
    unawaited(_speak(phrases.join(', ')));
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    ++_session;
    _keys.setMethodCallHandler(null);
    final camera = _controller;
    if (camera != null) {
      unawaited(() async {
        if (camera.value.isStreamingImages) {
          await camera.stopImageStream();
        }
        await camera.dispose();
        if (_modelReady) _detector.close();
      }());
    } else if (_modelReady) {
      _detector.close();
    }
    _http.close();
    unawaited(_tts.stop());
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (camera != null && camera.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: 1 / camera.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(camera),
                      CustomPaint(painter: OverlayPainter(_results, _distances)),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: const Color(0xCC0F1B3D),
                padding: const EdgeInsets.fromLTRB(12, 8, 50, 8),
                child: ExcludeSemantics(
                  child: Text(
                    _colabWarning == null ? _status : '$_status\n$_colabWarning',
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: _showColabSettings,
                icon: const Icon(Icons.settings, color: Colors.white),
                tooltip: 'Connect Google Colab distance',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its controller until the dialog is actually unmounted, including
/// the route's closing animation.
class _ColabSettingsDialog extends StatefulWidget {
  const _ColabSettingsDialog({
    required this.initialUrl,
    required this.applyUrl,
  });

  final String initialUrl;
  final Future<void> Function(String) applyUrl;

  @override
  State<_ColabSettingsDialog> createState() => _ColabSettingsDialogState();
}

class _ColabSettingsDialogState extends State<_ColabSettingsDialog> {
  late final TextEditingController _input;
  bool _connecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit(String url) async {
    if (_connecting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _connecting = true;
      _errorMessage = null;
    });
    try {
      await widget.applyUrl(url);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_connecting,
      child: AlertDialog(
        title: const Text('Connect distance to Colab'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('YOLO detection runs on the phone. Paste the '
                'Update 10 API PUBLIC URL for distance estimates.'),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              enabled: !_connecting,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Colab HTTPS URL',
                hintText: 'https://example.trycloudflare.com',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _connecting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _connecting ? null : () => _submit(''),
            child: const Text('Disconnect'),
          ),
          FilledButton(
            onPressed: _connecting ? null : () => _submit(_input.text),
            child: Text(_connecting ? 'Connecting…' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
