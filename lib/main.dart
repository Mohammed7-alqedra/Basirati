import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  static const _depthUrl =
      'https://huggingface.co/litert-community/'
      'Depth-Anything-V2-Metric-Hypersim-Small/resolve/main/'
      'Depth-Anything-V2-Metric-Hypersim-Small-fp32.tflite';

  CameraController? _camera;
  OfflineMayaPipeline? _pipeline;
  Timer? _timer;
  MayaFrame? _result;
  bool _initializing = false;
  bool _processing = false;
  int _session = 0;
  String _status = 'Prepare models once with Wi-Fi before going to university.';

  Future<File> _cachedDepthFile() async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory('${root.path}/models');
    await folder.create(recursive: true);
    return File('${folder.path}/maya_hypersim_small.tflite');
  }

  Future<File> _obtainDepthFile() async {
    final file = await _cachedDepthFile();
    // Do not trust a tiny HTML response or Git-LFS pointer as a model.
    if (await file.exists() && await file.length() >= 90000000) {
      return file;
    }

    final partial = File('${file.path}.download');
    final client = HttpClient();
    try {
      if (mounted) {
        setState(() => _status =
            'Downloading Maya Depth Anything V2 (~99 MB). Wi-Fi is needed once.');
      }
      final request = await client.getUrl(Uri.parse(_depthUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Depth model download returned HTTP ${response.statusCode}');
      }
      if (await partial.exists()) await partial.delete();
      final writer = partial.openWrite();
      await writer.addStream(response);
      await writer.flush();
      await writer.close();

      if (await partial.length() < 90000000) {
        throw StateError('Downloaded file is too small to be the expected model.');
      }
      // A TFLite FlatBuffer has the TFL3 identifier at byte offsets 4..7.
      final header = await partial.open();
      try {
        await header.setPosition(4);
        final bytes = await header.read(4);
        if (String.fromCharCodes(bytes) != 'TFL3') {
          throw StateError('Downloaded file is not a TFLite model.');
        }
      } finally {
        await header.close();
      }
      if (await file.exists()) await file.delete();
      return await partial.rename(file.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _start() async {
    if (_initializing || _pipeline != null) return;
    setState(() {
      _initializing = true;
      _status = 'Preparing models for offline use...';
    });

    OfflineMayaPipeline? pipeline;
    CameraController? camera;
    try {
      final modelFile = await _obtainDepthFile();
      if (mounted) {
        setState(() => _status =
            'Loading YOLO26n and Depth Anything. First setup may need internet.');
      }
      pipeline = await OfflineMayaPipeline.load(modelFile.path);

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
      _status = 'Stopped. Models remain on the phone for next time.';
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
                  'Prepare once on Wi-Fi, then test in airplane mode.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _initializing ? null : _start,
                  child: Text(_initializing
                      ? 'Preparing the offline models...'
                      : 'Prepare / Start offline models'),
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
        rect.left.clamp(0.0, size.width),
        (rect.top - painter.height).clamp(0.0, size.height),
      ));
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectBoxesPainter old) => old.objects != objects;
}
