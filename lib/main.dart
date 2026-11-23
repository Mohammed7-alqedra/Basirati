import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'offline_maya_pipeline.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BasiratiApp());
}

class BasiratiApp extends StatelessWidget {
  const BasiratiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basirati - Offline Maya Models',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const OfflineCameraScreen(),
    );
  }
}

class OfflineCameraScreen extends StatefulWidget {
  const OfflineCameraScreen({super.key});

  @override
  State<OfflineCameraScreen> createState() => _OfflineCameraScreenState();
}

class _OfflineCameraScreenState extends State<OfflineCameraScreen> {
  CameraController? _camera;
  OfflineMayaPipeline? _pipeline;
  Timer? _timer;
  MayaFrame? _result;
  bool _initializing = false;
  bool _processing = false;
  int _session = 0;
  String _status = 'AI models are bundled with the app. No server or internet needed.';

  Future<void> _start() async {
    if (_initializing || _pipeline != null) return;
    setState(() {
      _initializing = true;
      _status = 'Loading bundled AI models...';
    });

    OfflineMayaPipeline? pipeline;
    CameraController? camera;
    try {
      pipeline = await OfflineMayaPipeline.load();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera available');
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      camera = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        await pipeline.close();
        return;
      }

      final session = ++_session;
      setState(() {
        _pipeline = pipeline;
        _camera = camera;
        _result = null;
        _status = 'Both models loaded locally. Colab is NOT needed.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_processCameraFrame(session)),
      );
      unawaited(_processCameraFrame(session));
    } catch (error) {
      if (camera != null && !identical(camera, _camera)) {
        await camera.dispose();
      }
      if (pipeline != null && !identical(pipeline, _pipeline)) {
        await pipeline.close();
      }
      if (mounted) setState(() => _status = 'Setup failed: $error');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _processCameraFrame(int session) async {
    final camera = _camera;
    final pipeline = _pipeline;
    if (_processing || !mounted || session != _session ||
        camera == null || pipeline == null ||
        !camera.value.isInitialized || camera.value.isTakingPicture) return;

    _processing = true;
    try {
      final photo = await camera.takePicture();
      final bytes = await photo.readAsBytes();
      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (!mounted || session != _session) return;
      final next = await pipeline.process(bytes);
      if (!mounted || session != _session) return;

      setState(() {
        _result = next;
        _status = 'Offline inference: ${next.objects.length} objects detected. '
            'Distances are experimental.';
      });
    } catch (error) {
      if (mounted && session == _session) {
        setState(() => _status = 'Processing failed: $error');
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _stop() async {
    ++_session;
    _timer?.cancel();
    _timer = null;
    final oldCamera = _camera;
    final oldPipeline = _pipeline;
    setState(() {
      _camera = null;
      _pipeline = null;
      _result = null;
      _status = 'Stopped. Models are bundled inside the app.';
    });
    await oldCamera?.dispose();
    await oldPipeline?.close();
  }

  @override
  void dispose() {
    ++_session;
    _timer?.cancel();
    final camera = _camera;
    final pipeline = _pipeline;
    if (camera != null) unawaited(camera.dispose());
    if (pipeline != null) unawaited(pipeline.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final camera = _camera;

    return Scaffold(
      appBar: AppBar(title: const Text('Basirati - Offline Models')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (camera == null) ...[
                const Text(
                  'YOLO26n + Depth Anything V2 Metric Hypersim Small. '
                  'Both AI models are included in the APK. No Colab or server needed.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _initializing ? null : _start,
                  child: Text(_initializing
                      ? 'Loading local models...'
                      : 'Start camera and AI'),
                ),
              ] else ...[
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (result == null) {
                        return Center(child: CameraPreview(camera));
                      }
                      final scale = math.min(
                        constraints.maxWidth / result.width,
                        constraints.maxHeight / result.height,
                      );
                      return Center(
                        child: SizedBox(
                          width: result.width * scale,
                          height: result.height * scale,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.memory(
                                  result.jpeg,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ObjectBoxesPainter(result.objects),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text('Detected objects and approximate distances',
                    style: Theme.of(context).textTheme.titleMedium),
                Expanded(
                  child: ListView(
                    children: (result?.objects ?? const <MayaObject>[]).map((d) {
                      final distance = d.estimatedMeters == null
                          ? 'distance unavailable'
                          : '${d.estimatedMeters!.toStringAsFixed(2)} m (test)';
                      return Text('${d.name}: $distance');
                    }).toList(),
                  ),
                ),
                OutlinedButton(onPressed: _stop, child: const Text('Stop camera')),
              ],
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 8),
              const Text(
                'No Colab or server connection. Test distance accuracy against '
                'measured objects; never rely on these readings for safe navigation.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObjectBoxesPainter extends CustomPainter {
  const _ObjectBoxesPainter(this.objects);

  final List<MayaObject> objects;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final d in objects) {
      final box = d.box;
      final rect = Rect.fromLTRB(
        box.left * size.width, box.top * size.height,
        box.right * size.width, box.bottom * size.height,
      );
      canvas.drawRect(rect, pen);
      final distance = d.estimatedMeters;
      final label = distance == null
          ? d.name
          : '${d.name} ${distance.toStringAsFixed(2)}m';
      final painter = TextPainter(
        text: TextSpan(text: label,
            style: const TextStyle(color: Colors.greenAccent,
                fontSize: 13, backgroundColor: Colors.black87)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(canvas, Offset(
        rect.left.clamp(0.0, size.width).toDouble(),
        (rect.top - painter.height).clamp(0.0, size.height).toDouble(),
      ));
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectBoxesPainter old) => old.objects != objects;
}
