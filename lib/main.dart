import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'detection/yolo_detector.dart';
import 'l10n/app_localizations.dart';
import 'ui/overlay_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BaseerteApp());
}

class BaseerteApp extends StatelessWidget {
  const BaseerteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const MethodChannel _keys = MethodChannel('basirati/keys');

  final YoloDetector _detector = YoloDetector();
  final FlutterTts _tts = FlutterTts();

  CameraController? _controller;

  List<Detection> _results = [];

  int _processedImages = 0;
  int _processingMs = 0;
  final Stopwatch _sessionTimer = Stopwatch();

  double get _averageFps {
    final seconds = _sessionTimer.elapsedMilliseconds / 1000;
    return seconds > 0 ? _processedImages / seconds : 0;
  }

  bool _loading = true;
  bool _busy = false;
  bool _detectorLoaded = false;
  bool _streamStarted = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    unawaited(WakelockPlus.enable());

    _keys.setMethodCallHandler(_onKey);

    _initializeCameraAndDetection();
  }

  Future<void> _initializeCameraAndDetection() async {
    try {
      final cameraPermission = await Permission.camera.request();

      if (!mounted) return;

      if (!cameraPermission.isGranted) {
        setState(() {
          _error = 'CAMERA_PERMISSION_DENIED';
          _loading = false;
        });
        return;
      }

      await Permission.microphone.request();

      if (!mounted) return;

      if (!_detectorLoaded) {
        await _detector.load();
        _detectorLoaded = true;
      }

      final cameras = await availableCameras();

      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _error = 'NO_CAMERA_FOUND';
          _loading = false;
        });
        return;
      }

      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final cameraController = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await cameraController.initialize();

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      _controller = cameraController;

      setState(() {
        _loading = false;
        _error = null;
      });

      await cameraController.startImageStream(_onFrame);

      _streamStarted = true;

      if (!mounted) return;

      await _speak(AppLocalizations.of(context)!.assistanceActive);
    } catch (e) {
      debugPrint('Camera or detection initialization failed: $e');

      final failedController = _controller;
      _controller = null;
      _streamStarted = false;

      if (failedController != null) {
        unawaited(failedController.dispose());
      }

      if (!mounted) return;

      setState(() {
        _error = _detectorLoaded
            ? 'CAMERA_UNAVAILABLE'
            : 'DETECTION_UNAVAILABLE';
        _loading = false;
      });
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy || _controller == null) return;

    _busy = true;
    if (!_sessionTimer.isRunning) _sessionTimer.start();

    try {
      final stopwatch = Stopwatch()..start();
      final detections = _detector.detect(
        image,
        _controller!.description.sensorOrientation,
      );
      stopwatch.stop();

      if (mounted) {
        setState(() {
          _results = detections;
          _processedImages++;
          _processingMs = stopwatch.elapsedMilliseconds;
        });
      }
    } catch (e) {
      debugPrint('YOLO detection error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _onKey(MethodCall call) async {
    if (!mounted) return;

    if (call.method == 'volumeUpLong') {
      await _describeObjects();
    } else if (call.method == 'volumeUpShort') {
      final l10n = AppLocalizations.of(context)!;
      await _speak(l10n.roomNumberNotReady);
    }
  }

  String _localizedObjectLabel(Detection detection, AppLocalizations l10n) {
    switch (detection.classId) {
      case 0:
        return l10n.objectPerson;
      case 1:
        return l10n.objectBicycle;
      case 2:
        return l10n.objectCar;
      case 3:
        return l10n.objectMotorcycle;
      case 5:
        return l10n.objectBus;
      case 7:
        return l10n.objectTruck;
      case 13:
        return l10n.objectBench;
      case 24:
        return l10n.objectBackpack;
      case 26:
        return l10n.objectHandbag;
      case 28:
        return l10n.objectSuitcase;
      case 39:
        return l10n.objectBottle;
      case 41:
        return l10n.objectCup;
      case 56:
        return l10n.objectChair;
      case 57:
        return l10n.objectCouch;
      case 58:
        return l10n.objectPottedPlant;
      case 60:
        return l10n.objectDiningTable;
      case 61:
        return l10n.objectToilet;
      case 62:
        return l10n.objectTv;
      case 63:
        return l10n.objectLaptop;
      case 64:
        return l10n.objectMouse;
      case 66:
        return l10n.objectKeyboard;
      case 67:
        return l10n.objectCellPhone;
      case 68:
        return l10n.objectMicrowave;
      case 71:
        return l10n.objectSink;
      case 72:
        return l10n.objectRefrigerator;
      case 73:
        return l10n.objectBook;
      case 74:
        return l10n.objectClock;
      default:
        return l10n.noObjectsDetected;
    }
  }

  String _localizedDirection(String direction, AppLocalizations l10n) {
    switch (direction) {
      case 'left':
        return l10n.directionLeft;
      case 'right':
        return l10n.directionRight;
      default:
        return l10n.directionAhead;
    }
  }

  String _pluralizeEnglish(int classId, String label) {
    if (classId == 0) return 'people';
    if (classId == 64) return 'mice';
    if (classId == 62) return 'TVs';

    return '${label}s';
  }

  Future<void> _describeObjects() async {
    if (_results.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      await _speak(l10n.noObjectsDetected);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final groups = <String, int>{};
    final objects = <String, Detection>{};

    for (final detection in _results) {
      final key = '${detection.classId}|${detection.direction}';

      groups[key] = (groups[key] ?? 0) + 1;
      objects[key] = detection;
    }

    final phrases = <String>[];

    for (final entry in groups.entries) {
      final detection = objects[entry.key]!;

      final label = _localizedObjectLabel(detection, l10n);

      final count = entry.value;

      final name = isArabic
          ? '$count $label'
          : count == 1
          ? label
          : '$count ${_pluralizeEnglish(detection.classId, label)}';

      final direction = _localizedDirection(detection.direction, l10n);

      phrases.add('$name $direction');
    }

    await _speak(phrases.join(', '));
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;

    final language = Localizations.localeOf(context).languageCode;

    try {
      await _tts.stop();

      if (!mounted) return;

      await _tts.setLanguage(language == 'ar' ? 'ar' : 'en-US');

      if (!mounted) return;

      await _tts.speak(text);
    } catch (e) {
      debugPrint('Text to speech error: $e');
    }
  }

  String _getErrorMessage(AppLocalizations l10n) {
    switch (_error) {
      case 'CAMERA_PERMISSION_DENIED':
        return l10n.cameraPermissionDenied;

      case 'NO_CAMERA_FOUND':
        return l10n.noCameraFound;

      case 'DETECTION_UNAVAILABLE':
        return l10n.detectionUnavailable;

      default:
        return l10n.cameraUnavailable;
    }
  }

  @override
  void dispose() {
    _keys.setMethodCallHandler(null);

    final controller = _controller;

    if (controller != null) {
      if (_streamStarted) {
        unawaited(controller.stopImageStream());
      }

      unawaited(controller.dispose());
    }

    if (_detectorLoaded) {
      _detector.close();
    }

    unawaited(_tts.stop());
    unawaited(WakelockPlus.disable());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _controller;

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              DrawerHeader(
                child: Center(
                  child: Text(
                    l10n.appName,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(l10n.settings),
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (controller?.value.isInitialized == true)
                Center(
                  child: AspectRatio(
                    aspectRatio: 1 / controller!.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        CustomPaint(
                          painter: OverlayPainter(
                            _results,
                            textForDetection: (detection) {
                              final label = _localizedObjectLabel(
                                detection,
                                l10n,
                              );

                              final direction = _localizedDirection(
                                detection.direction,
                                l10n,
                              );

                              return '$label · $direction';
                            },
                            textDirection: Directionality.of(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _getErrorMessage(l10n),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });

                                _initializeCameraAndDetection();
                              },
                              child: Text(l10n.tryAgain),
                            ),
                          ],
                        ),
                ),

              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: IconButton(
                    tooltip: l10n.openSettingsMenu,
                    icon: const Icon(Icons.menu, size: 32),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
              ),

              if (controller?.value.isInitialized == true)
                Positioned(
                  top: 65,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xDD0F1B3D),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Images processed: $_processedImages\n'
                          'Elapsed time: ${(_sessionTimer.elapsedMilliseconds / 1000).toStringAsFixed(1)} s\n'
                          'Last image: $_processingMs ms\n'
                          'Average FPS: ${_averageFps.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (controller?.value.isInitialized == true)
                Positioned(
                  top: 8,
                  right: 12,
                  child: SafeArea(
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F1B3D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l10n.assistanceActive,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: Center(child: Text(l10n.settingsDescription)),
    );
  }
}
