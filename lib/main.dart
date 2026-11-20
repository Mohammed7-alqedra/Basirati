import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'detection/yolo_detector.dart';
import 'depth/depth_estimator.dart';
import 'depth/depth_calibration.dart';
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
  final DepthEstimator _depth = DepthEstimator();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String _samplesKey = 'baseerte_depth_samples_v2';
  final List<CalibrationSample> _samples = [];
  bool _calibrationLoaded = false;
  bool _depthReady = false;
  String? _depthStatus;
  int _depthFrame = 0;
  final FlutterTts _tts = FlutterTts();

  CameraController? _controller;

  List<Detection> _results = [];
  Detection? _lastMatchedDetection;
  DateTime? _lastMatchedAt;

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

  void _updateCalibration() {
    final calibration = DepthCalibration.fit(_samples);
    _depth.setCalibration(calibration);
    _depthStatus = calibration == null
        ? 'Distance TEST: RAW only — add 3+ measured samples'
        : 'Distance TEST: calibrated with ${_samples.length} samples — not verified';
  }

  Future<void> _loadCalibration() async {
    try {
      final stored = await _preferences.getString(_samplesKey);
      if (stored != null) {
        final parsed = jsonDecode(stored);
        if (parsed is List) {
          for (final item in parsed) {
            final sample = CalibrationSample.fromJson(item);
            if (sample != null) _samples.add(sample);
          }
        }
      }
    } catch (e) {
      debugPrint('Could not load distance samples: $e');
    }
    _updateCalibration();
  }

  Future<void> _saveCalibration() async {
    try {
      await _preferences.setString(
        _samplesKey,
        jsonEncode(_samples.map((sample) => sample.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Could not save distance samples: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Distance samples could not be saved.')),
        );
      }
    }
  }

  Detection? _centerObjectWithDepth(List<Detection> detections) {
    final visible = detections
        .where((d) => d.rawMeters != null &&
            d.rawMeters!.isFinite &&
            d.rawMeters! > 0)
        .toList();
    if (visible.isEmpty) return null;

    // Prefer the object closest to the middle of the image.
    double centerDistance(Detection d) {
      final dx = d.centerX - 0.5;
      final dy = (d.top + d.bottom) / 2 - 0.5;
      return dx * dx + dy * dy;
    }

    visible.sort((a, b) =>
        centerDistance(a).compareTo(centerDistance(b)));
    return visible.first;
  }

  Detection? _objectForCalibration() {
    if (_lastMatchedAt == null ||
        DateTime.now().difference(_lastMatchedAt!) >
            const Duration(seconds: 5)) {
      return null;
    }
    return _lastMatchedDetection;
  }

  Future<void> _captureCalibrationSample() async {
    final detection = _objectForCalibration();
    if (detection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Point at one detected object and try again.',
        )),
      );
      return;
    }

    final raw = detection.rawMeters!;
    String inputValue = '';
    String? error;

    final measured = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogSetState) => AlertDialog(
          title: const Text('Add distance measurement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Detected object: ${detection.label}'),
                Text('Raw AI depth: ${raw.toStringAsFixed(2)} m'),
                const SizedBox(height: 12),
                const Text(
                  'Use a tape measure from the camera lens to this '
                  'object. Enter its actual distance in meters.',
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => inputValue = value,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Actual distance (m)',
                    hintText: 'Example: 1.90',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('This is experimental; do not use for navigation.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    double.tryParse(inputValue.trim().replaceAll(',', '.'));
                if (value == null || !value.isFinite ||
                    value <= 0 || value > 20) {
                  dialogSetState(() {
                    error = 'Enter a distance above 0 and at most 20 meters.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Save sample'),
            ),
          ],
        ),
      ),
    );
    if (measured == null || !mounted) return;

    setState(() {
      _samples.add(CalibrationSample(
        rawMeters: raw,
        actualMeters: measured,
      ));
      _updateCalibration();
    });
    await _saveCalibration();

    if (mounted) {
      final calibration = DepthCalibration.fit(_samples);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          calibration == null
              ? 'Saved ${_samples.length} sample(s). '
                'Use different measured distances (e.g. 0.5, 1, 2, 3 m).'
              : 'Calibration fitted from ${_samples.length} samples '
                '(TEST only). Verify using new distances.',
        )),
      );
    }
  }

  Future<void> _resetCalibration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear calibration?'),
        content: const Text(
          'This deletes all saved tape-measured samples '
          'and returns to uncalibrated raw readings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear samples'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _samples.clear();
      _updateCalibration();
    });
    await _saveCalibration();
  }

  Future<void> _showCalibrationDetails() async {
    final fitted = DepthCalibration.fit(_samples);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Calibration test'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved samples: ${_samples.length}'),
              const SizedBox(height: 8),
              Text(fitted == null
                  ? 'Not calibrated. Capture at least 3 samples at '
                    'different known distances, at least 0.5 m apart overall.'
                  : 'Fitted formula (TEST): '
                    '${fitted.slope.toStringAsFixed(4)} × raw + '
                    '${fitted.intercept.toStringAsFixed(4)}'),
              const SizedBox(height: 12),
              for (var i = 0; i < _samples.length; i++)
                Text(
                  '${i + 1}. Raw ${_samples[i].rawMeters.toStringAsFixed(2)} m'
                  ' → tape ${_samples[i].actualMeters.toStringAsFixed(2)} m',
                ),
              const SizedBox(height: 12),
              const Text(
                'Use different measured distances and retest using '
                'distances that were NOT used for calibration. '
                'Distance warnings remain disabled.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _samples.isEmpty
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _resetCalibration();
                  },
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeCameraAndDetection() async {
    try {
      if (!_calibrationLoaded) {
        await _loadCalibration();
        _calibrationLoaded = true;
      }
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
        try {
          await _depth.load();
          _depthReady = true;
          _updateCalibration();
        } catch (e) {
          _depthStatus = 'Depth model missing or unavailable';
          debugPrint('Depth load error: $e');
        }
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

    try {
      final rotation = _controller!.description.sensorOrientation;
      final detections = _detector.detect(image, rotation);
      if (_depthReady) {
        try {
          final isMatchedFrame = _depthFrame % 5 == 0 || !_depth.hasDepth;
          if (isMatchedFrame) {
            _depth.update(image, rotation);
          }
          for (final d in detections) {
            final reading = _depth.readingFor(d);
            d.meters = reading?.calibratedMeters;
            d.rawMeters = reading?.rawMeters;
          }
          // Save a sample ONLY from a frame processed by both models.
          // Other frames may use an older depth map and must not be
          // mixed into tape-measured calibration points.
          if (isMatchedFrame) {
            _lastMatchedDetection = _centerObjectWithDepth(detections);
            _lastMatchedAt = DateTime.now();
          }
        } catch (e) {
          _depthReady = false;
          _lastMatchedDetection = null;
          _depthStatus = 'Depth processing unavailable';
          debugPrint('Depth processing error: $e');
        }
      }
      _depthFrame++;

      if (mounted) {
        setState(() {
          _results = detections;
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
    _depth.close();

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

                              final distance = detection.meters;
                              final rawDistance = detection.rawMeters;
                              if (rawDistance == null) {
                                return '$label · $direction';
                              }
                              if (distance == null) {
                                return '$label · $direction\n'
                                    'raw ${rawDistance.toStringAsFixed(2)} m '
                                    '(uncalibrated)';
                              }
                              return '$label · $direction\n'
                                  'raw ${rawDistance.toStringAsFixed(2)} m → '
                                  'calibrated ${distance.toStringAsFixed(2)} m (test)';
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

              if (_depthStatus != null)
                Positioned(
                  top: 65,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    child: Text(
                      _depthStatus!,
                      style: const TextStyle(
                        color: Colors.white,
                        backgroundColor: Color(0xCC0F1B3D),
                      ),
                    ),
                  ),
                ),
              if (controller?.value.isInitialized == true && _depthReady)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _captureCalibrationSample,
                            icon: const Icon(Icons.add),
                            label: const Text('Add measured distance'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _showCalibrationDetails,
                          child: Text('Samples (${_samples.length})'),
                        ),
                      ],
                    ),
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
