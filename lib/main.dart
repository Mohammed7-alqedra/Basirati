import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'l10n/app_localizations.dart';

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
  CameraController? _controller;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission.
      final cameraPermission = await Permission.camera.request();

      if (!mounted) return;

      if (!cameraPermission.isGranted) {
        setState(() {
          _error = 'CAMERA_PERMISSION_DENIED';
          _loading = false;
        });
        return;
      }

      // Request microphone permission for future voice commands.
      await Permission.microphone.request();

      if (!mounted) return;

      // Find available cameras.
      final cameras = await availableCameras();

      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _error = 'NO_CAMERA_FOUND';
          _loading = false;
        });
        return;
      }

      // Prefer the rear camera.
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final cameraController = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await cameraController.initialize();

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      setState(() {
        _controller = cameraController;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'CAMERA_UNAVAILABLE';
        _loading = false;
      });

      debugPrint('Camera initialization failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _getErrorMessage(AppLocalizations l10n) {
    switch (_error) {
      case 'CAMERA_PERMISSION_DENIED':
        return l10n.cameraPermissionDenied;

      case 'NO_CAMERA_FOUND':
        return l10n.noCameraFound;

      default:
        return l10n.cameraUnavailable;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
              if (_controller?.value.isInitialized == true)
                CameraPreview(_controller!)
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

                                _initializeCamera();
                              },
                              child: Text(l10n.tryAgain),
                            ),
                          ],
                        ),
                ),

              // Menu button at the top left.
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
