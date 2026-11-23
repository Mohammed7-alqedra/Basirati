# Basirati AI — bundled models, no server

This Android branch embeds **both** of Maya's AI models in the application
package. The phone does all inference; nothing is uploaded to a server.

- **YOLO26n** detects objects using the Ultralytics Android LiteRT
  `yolo26n_w8a32.tflite` export.
- **Depth Anything V2 Metric Hypersim Small** estimates depth with the
  `Depth-Anything-V2-Metric-Hypersim-Small-fp32.tflite` Android model
  derived from the notebook's indoor metric checkpoint.

The original notebook is retained in the repository but is **not** executed
by the Android app. The older YOLO11n or stair-detection models are not used.

## One-time development setup (Windows PowerShell)

**Important: model binaries are not checked into GitHub.** They are large
binary assets and must be placed in the project *before building the APK*.
The included PowerShell script downloads them to your local project's
`assets/models/` directory, validates their binary headers, and keeps them
as APK assets. This is a **development-time download only**; end users do not
download models, and the Android app requires no internet.

From the repository root:

```powershell
git switch feature/maya-models-offline
git pull --ff-only origin feature/maya-models-offline
.\tool\download_models.ps1
flutter pub get
flutter analyze
flutter test
flutter run --profile
```

If your PowerShell execution policy prevents running the script, run it for
this invocation using:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\download_models.ps1
```

It downloads:
- `assets/models/yolo26n_w8a32.tflite` (~2.9 MB), pinned to the official
  Ultralytics Flutter v0.7.0 detection release.
- `assets/models/depth_anything_v2_metric_hypersim_small.tflite`
  (~99 MB), the Hypersim Small **metric** depth export.

The files must be genuine TFLite models, **not** Git LFS pointer files.
`pubspec.yaml` references them explicitly: Flutter cannot produce a
working APK unless both are present.

After installation, turn on Airplane Mode and test again. Users of the
installed APK need no Colab, hosted GPU, laptop, model download, or API key.

## How inference works

One camera image is captured about every three seconds, then both model
outputs are combined:

1. YOLO26n provides object labels and boxes (confidence threshold 0.25).
2. Depth Anything V2 estimates metric depth for a center-cropped 518×518
   image.
3. Each object uses the positive finite **median depth in its central
   60%** (20% margin on all sides).
4. Distance estimate = `max(0, 1.05 * median_depth - 0.10)` metres.

These constants are copied from Maya's notebook. The mobile crop differs
from the notebook's full-image aspect-preserving resize, so exact numerical
parity cannot be assumed. Objects outside the depth crop may have no
distance reading.

## Limitations and warnings

- **Performance will not automatically improve by embedding the models.**
  Both still run on the phone. In particular, Depth Anything V2 (~99 MB) is
  demanding, and the Galaxy A32 is likely to struggle. Processing may cause
  long pauses and battery drain. Measure both phones with a profile build.
- The app captures snapshots, not a smooth live inference stream.
- Flutter analysis and tests must still be executed locally; on-device
  loading, performance, and distance accuracy remain unverified.
- Depth readings are estimates and **must not be used to guide blind or
  visually impaired users around hazards** until rigorously validated.
- Review Ultralytics and Depth Anything model licenses before distributing
  APKs or publishing the app.
- GitHub excludes model binaries to avoid pushing very large files in normal
  Git commits. The **built APK includes them** once downloaded locally.

Source model references:
- https://github.com/ultralytics/yolo-flutter-app/releases/tag/v0.7.0
- https://huggingface.co/litert-community/Depth-Anything-V2-Metric-Hypersim-Small

The previous server-hosted prototype remains on the separate
`feature/server-hosted-maya` branch, and the Colab client on `main`
remains untouched.
