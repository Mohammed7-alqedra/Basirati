# Baseerte AI — supplied YOLO11 detector + Colab depth

The on-device detector in this branch comes from the uploaded
`basirati_for_det(1).zip` package, not the earlier experimental
`ultralytics_yolo` code.

| Component | Where it runs | File |
| --- | --- | --- |
| YOLO11n (320×320, TFLite) | Android phone | `lib/detection/yolo_detector.dart` |
| Model and labels | Bundled in APK | `assets/yolo11n.tflite`, `assets/labels.txt` |
| Camera and volume-key voice controls | Android/Flutter | `lib/main.dart`, `android/app/src/main/kotlin/com/baseerte/baseerte_ai/MainActivity.kt` |
| Bounding boxes | Android/Flutter | `lib/ui/overlay_painter.dart` |
| YUV420 frame -> upright JPEG | Phone, sampled while streaming | `lib/depth/frame_encoder.dart` |
| Depth API HTTP transport | Android phone | `lib/depth/colab_depth_client.dart` |
| Depth Anything V2 & calibration | Google Colab **only** | `Maya Alsuos update 10.ipynb` |

## Exact YOLO model included in the repository

The supplied model is **10,688,099 bytes** with SHA-256:
`eb9b233b9e339fb5ef83926be5c70e0f7fab286c0b30979617d8622dadc7b157`.

The original model binary was too large for a single GitHub connector upload.
To preserve it **exactly**, the GitHub repository stores 28 base64 text assets
in `assets/model_segments/`. On application startup, `YoloDetector.load()`
reassembles the bytes **in memory** and passes them to
`tflite_flutter.Interpreter.fromBuffer`. This is still a **local, on-device**
YOLO model and requires **no internet or Colab** to detect objects.

You do **not** have to copy the model manually after `git pull`.
The integration ZIP also contains the original standalone
`assets/yolo11n.tflite` for verification or use outside this build.

The model uses float32 input `[1,3,320,320]` and output `[1,84,2100]`.

## Run in Google Colab

1. Upload/open `Maya Alsuos update 10.ipynb`.
2. Select a GPU runtime if available and execute notebook cells 0–14.
3. Copy the `API PUBLIC URL` ending in `.trycloudflare.com`.
4. Open `<URL>/health` and confirm `"yolo_in_colab": false`.
5. On your phone, open Baseerte AI, tap the **settings icon** in the
   upper-right corner and paste the base HTTPS URL; tap **Connect**.

Object detection works entirely on the phone. Distance estimation requires
Colab to remain running. The tunnel URL changes when the Colab runtime restarts.

## Technical detail

- YOLO runs on **YUV420 camera-stream frames**, without `takePicture()`.
- About once every 1.8 seconds (when a Colab request is not in flight), the
  same camera frame is converted on a worker isolate into a 640px-or-smaller
  upright JPEG. The sampled JPEG + normalized boxes are uploaded via
  multipart `POST /estimate-depth` (`file`, `detections`).
- The Colab notebook returns `calibrated_distance_m`. The app associates a
  distance with a **matching class and overlapping box**, not just a name.
  Readings are hidden when too old, or when a matching object disappears.
- Long-press **Volume Up** to hear object names/directions; when a recent
  Colab distance exists, speech includes it. Short Volume Up keeps the
  supplied placeholder for room-number reading.
- Bounding boxes are **yellow** for obstacle classes, **teal** for info
  classes. The ZIP's 80-label COCO model has no dedicated `stairs` class.
- Uploading the camera image over a temporary unauthenticated Cloudflare
  tunnel is suitable for consented prototypes only.

## Build

From your project root:

```powershell
git pull --ff-only origin main
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
```

The memory setting in `android/gradle.properties` remains 4 GB **maximum
Gradle build heap on the computer**, not Android-phone RAM.

The local YOLO runtime and camera stream need testing on the target Samsung
phone. Depth values are experimental; they must not be used for safe
navigation or obstacle avoidance without independent validation.
