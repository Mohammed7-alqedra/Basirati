# Baseerte AI — object detection + depth prototype

This branch adds the supplied Depth Anything V2 indoor model integration alongside YOLO, while keeping the existing camera UI, translations, settings, and Volume Up voice control. It is separate from `main`.

## REQUIRED: copy the large depth model locally

The file `assets/depth_indoor.tflite` (97,954,264 bytes) is **not in this Git branch** due to binary upload limitations. Download/use the `depth_indoor.tflite` file supplied in the project chat, and copy it into the Flutter project's `assets` folder before building. The existing `assets/yolo11n.tflite` remains in the repository.

In Android Studio Terminal:

```powershell
git fetch origin
git switch feature/object-distance-ai
flutter pub get
flutter analyze
flutter run --profile
```

Before running, confirm `assets/depth_indoor.tflite` exists. The `pubspec.yaml` declares it; Flutter packaging fails without it.

## Scope, limits, and safety

- YOLO object detection is preserved; depth runs every 5th processed frame.
- Object labels may show `~1.8 m (test)`. **Do not interpret these as validated metric distances.** They are raw depth-model predictions without device-specific calibration.
- No automatic proximity warning is enabled. Do not use this prototype for independent walking/navigation or safety-critical obstacle avoidance.
- Processing is still synchronous on Flutter's main isolate and may be slower due to the second model.
- This change has not been built or tested on the S25 Ultra. Run `flutter analyze` and verify camera permissions and model compatibility locally.
- If depth fails to load at runtime, YOLO should still work and a depth status is displayed.

To roll back safely, switch to `main` with a clean working tree: `git switch main`.
