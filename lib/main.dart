import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'detection/stairs_detector.dart';
import 'detection/yolo_detector.dart';
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

/// Opens the camera automatically and runs object detection on the live stream.
/// Phase 1: boxes are drawn for team testing.
/// Long-press Volume Up: says which objects are in front. No on-screen buttons:
/// the app is used exactly like a blind user would use it.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // Volume keys come from android/.../MainActivity.kt through this channel.
  static const _keys = MethodChannel('basirati/keys');

  final _detector = YoloDetector();
  final _tts = FlutterTts();
  CameraController? _controller;
  List<Detection> _results = [];
  bool _busy = false;
  String _status = 'Starting camera…';

  // ---------- Stairs (added) ----------
  final _stairs = StairsDetector();
  final _stairsAlert = StairsAlert();
  bool _stairsReady = false;
  int _frameCount = 0;
  List<Detection> _stairsResults = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep the screen on, or the camera stops
    _keys.setMethodCallHandler(_onKey);
    _start();
  }

  Future<void> _start() async {
    try {
      await _detector.load();
      // Stairs model: if it fails to load, the rest of the app keeps working.
      try {
        await _stairs.load();
        _stairsReady = true;
      } catch (e) {
        debugPrint('Stairs model not loaded: $e');
      }
      await _tts.setLanguage('en-US');

      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // The camera plugin asks for the camera permission here (first time only).
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _status = 'Started';
      });
      await controller.startImageStream(_onFrame);
      _speak('Started');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  void _onFrame(CameraImage image) {
    // Skip frames while the model is busy, so we always use a recent frame.
    if (_busy || _controller == null) return;
    _busy = true;
    final start = DateTime.now();
    try {
      final results =
          _detector.detect(image, _controller!.description.sensorOrientation);
      _checkStairs(image);
      final ms = DateTime.now().difference(start).inMilliseconds;
      final fps = ms > 0 ? 1000 ~/ ms : 0;
      if (mounted) {
        setState(() {
          _results = results;
          _status = '${results.length} objects · $ms ms per frame (about $fps FPS)';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Detection error: $e');
    } finally {
      _busy = false;
    }
  }

  /// Stairs model runs on every 3rd frame (stairs don't move).
  /// Any error turns the stairs check off; the rest of the app keeps working.
  void _checkStairs(CameraImage image) {
    if (!_stairsReady) return;
    _frameCount++;
    if (_frameCount % 3 != 1) return;
    try {
      _stairsResults =
          _stairs.detect(image, _controller!.description.sensorOrientation);
      final message = _stairsAlert.update(_stairsResults, DateTime.now());
      if (message != null) _speak(message);
    } catch (e) {
      _stairsReady = false;
      _stairsResults = [];
      debugPrint('Stairs model error: $e');
    }
  }

  // ---------- Volume keys ----------
  Future<void> _onKey(MethodCall call) async {
    if (call.method == 'volumeUpLong') {
      _describeObjects();
    } else if (call.method == 'volumeUpShort') {
      _speak('Room number reading is not ready yet');
    }
  }

  /// Says every object currently seen, grouped by name and direction.
  void _describeObjects() {
    final results = _results;
    if (results.isEmpty) {
      _speak("I don't see any objects");
      return;
    }
    final groups = <String, int>{};
    for (final d in results) {
      final key = '${d.label}|${d.direction}';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    final phrases = groups.entries.map((e) {
      final parts = e.key.split('|');
      final label = parts[0], direction = parts[1];
      final plural = label == 'person' ? 'people' : '${label}s';
      final name = e.value > 1 ? '${e.value} $plural' : label;
      final where = direction == 'left'
          ? 'on your left'
          : direction == 'right'
              ? 'on your right'
              : 'ahead';
      return '$name $where';
    });
    _speak(phrases.join(', '));
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _detector.close();
    _stairs.close();
    _tts.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (c != null && c.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: 1 / c.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(c),
                      CustomPaint(painter: OverlayPainter(_results)),
                      CustomPaint(painter: OverlayPainter(_stairsResults)),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: const Color(0xCC0F1B3D),
                padding: const EdgeInsets.all(12),
                // Hidden from TalkBack: it changes many times per second (team info only).
                child: ExcludeSemantics(
                  child: Text(
                    _status,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
