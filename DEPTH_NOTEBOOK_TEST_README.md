# Baseerte AI — test distance algorithm from uploaded notebook

This branch is an **experimental Flutter port of the distance calculation** in
`Untitled11 (2).ipynb`. It preserves YOLO detection and the existing Android app.
The original `main` branch and previous `feature/object-distance-ai` branch are unchanged.

## What has been replaced

- `lib/depth/depth_estimator.dart`: changes the object-distance calculation to
  take the **median of positive, finite depth values** inside a YOLO box with
  **20% trimmed from each edge** (notebook Cell 4).
- Applies notebook Cell 3 / Cell 5 calibration:
  `test_distance_m = max(0, 0.6341037631666971 * raw_depth_m + 0.401649701699875)`.
- Displays **both** `raw` and `test` values with the detected object's label,
  so readings can be checked against a measuring tape.
- Removes the prior on-screen processing statistics. Voice controls and
  localization are preserved.
- Leaves **automatic distance-based warnings OFF**.

## Important model limitation

A Python/Jupyter `.ipynb` file is **not** a TensorFlow Lite model and cannot be
run inside Flutter directly.

This branch **reuses the already supplied local** `assets/depth_indoor.tflite`.
The uploaded notebook loads a PyTorch
`Depth-Anything-V2-Metric-Hypersim-Small` checkpoint and does **not** contain
a conversion of that checkpoint into a new TFLite file. Therefore this code
change does NOT prove the phone has the exact weights used by the notebook.

The notebook's calibration values may also have been measured on different
images or preprocessing. This is a test, **not a verified accuracy fix**.

The app still prepares input using its existing Flutter camera YUV-to-RGB
conversion and nearest-neighbor resampling. The notebook does not establish
that this matches the original model's complete Python preprocessing.
Depth is updated every fifth processed frame, so hold the camera steady during
initial tests. If results remain inaccurate, verify exact model weights,
preprocessing, crop/rotation, and frame alignment before recalibrating.

## Install and run (Windows / Android Studio)

In a clean working tree:

```powershell
git status --short
git fetch origin
git switch feature/depth-notebook-test
Test-Path .\assets\depth_indoor.tflite
flutter pub get
flutter analyze
flutter run --profile
```

The `Test-Path` command must return `True`; if `False`, copy the
previously supplied `depth_indoor.tflite` into `assets` locally.
It is **not** present in this GitHub branch because of its size.

The first build may take some time. The new branch has not been compiled or
tested on the Samsung Galaxy S25 Ultra in this environment.

## Evaluate

Hold the phone still, normal rear camera at 1x, with a tape-measured object
at e.g. 0.5, 1.0, 1.5, 2.0, 3.0 meters. Record 5 readings per distance, both
`raw` and `test`. Compare against **new** photos/distances not used for
the existing slope/intercept.

Example: a raw 2.90 m would produce about 2.24 m with the notebook formula;
that is still incorrect for a true 1.90 m object. Smoothing cannot repair a
systematic error.

Do not use these measurements for blind navigation, obstacle alarms, or safety
decisions until validated with appropriate testing.

## Rollback

Switch back to the earlier experimental branch:
`git switch feature/object-distance-ai`, or to the working original:
`git switch main`, once your local tree is clean.
