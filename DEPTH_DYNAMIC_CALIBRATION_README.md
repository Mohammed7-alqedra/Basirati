# Baseerte AI — new notebook distance test (Untitled15 (3).ipynb)

**Branch:** `feature/depth-notebook-dynamic-calibration`

This replaces the **previous hard-coded calibration method** with the core
distance-calculation method from the newly uploaded notebook.

## What it does

- Loads the existing local `assets/depth_indoor.tflite` depth model.
- Keeps existing `assets/yolo11n.tflite` object detection and voice features.
- Uses YOLO boxes in place of the notebook's Colab-only, mouse-drag box picker.
- Gets the median of valid depth pixels inside the central 60% of an object box.
- Replaces the old fixed `slope=0.6341037631666971` and
  `intercept=0.401649701699875` with a linear fit calculated from
  tape-measured calibration points (`fit_calibration` in Cell 7).
- Saves calibration samples on the phone using `shared_preferences` so they
  survive app restarts. Use **Samples → Reset** to discard them.
- Displays **raw AI depth** before calibration, and
  **raw → calibrated (test)** once a fit is available.
- Captures a calibration point from the most recent frame processed by **both**
  YOLO and Depth Anything, not an arbitrary frame paired with an old depth map.
- Keeps distance-based safety warnings **OFF**.

The notebook requires 2 samples; this app deliberately requires **at least 3
samples spanning at least 0.5 meters** to reduce overfitting to a two-point
measurement. It also rejects a fit when the model's outputs do not vary or
when the fitted slope is not positive. Fitting happens automatically when
enough acceptable samples exist.

## What this does NOT replace

The uploaded notebook **does not include an exported .tflite model**.
It downloads the official PyTorch
`depth_anything_v2_metric_hypersim_vits.pth` checkpoint and calls
`DepthAnythingV2.infer_image` in Google Colab.

Flutter cannot execute the Colab notebook directly. The app therefore **still
uses your local** `depth_indoor.tflite`. We have not established that its
checkpoint, input resizing, rotation, or color preprocessing exactly matches
the notebook. A new TFLite binary would need to be provided or converted and
verified separately before claiming the model itself was replaced.

## Run on Windows / Samsung Galaxy S25 Ultra

In Android Studio Terminal:

```powershell
git status --short
git fetch origin
git switch feature/depth-notebook-dynamic-calibration
Test-Path .\assets\depth_indoor.tflite
flutter pub get
flutter analyze
flutter test test/depth_calibration_test.dart
flutter run --profile
```

`Test-Path` must be `True`. If it is `False`, the older downloaded file
needs to be restored to the `assets` directory on the computer.
The binary is intentionally not uploaded to GitHub.

If `git switch` reports conflicting local changes, stop and preserve
those local changes; do not force a checkout or delete the model.

## How to calibrate in the app

1. Use the rear camera at 1x zoom. Select a single clearly detected object
   near the center of the camera view in bright indoor lighting.
2. Place the phone a **tape-measured** distance from the object, e.g. 0.5 m.
3. Tap **Add measured distance**. Confirm the detected object and the raw AI
   reading, enter the tape measurement in **meters**, and tap **Save sample**.
4. Repeat on the same object at different known distances: e.g.
   1.0, 1.5, 2.0 and 3.0 m. Hold the phone as still as possible.
5. Tap **Samples (N)** to see the list and fitted slope/intercept.
6. After 3+ suitable samples, the overlay shows a **calibrated (test)** value.
7. Test on **new** tape-measured distances and different objects that were
   **not** included in the fit. Record the raw and corrected results.
8. Use **Samples → Reset** if samples were recorded on the wrong object,
   calibration becomes nonsensical, or the camera/model setup changes.

The app uses the YOLO object closest to the **middle of the frame**, not a
manual box picker, so ensure that this is the object being measured.
Calibration points only come from synchronized YOLO/depth frames, but the
on-screen depth labels can still use the most recently processed depth map
between those frames. This old-frame mismatch, preprocessing differences,
model behavior and camera geometry can still cause errors.

## Accuracy and safety

Fitting a line does not fix a fluctuating or fundamentally inaccurate depth
model. It does not make this app suitable for blind-navigation or obstacle
safety decisions. Leave distance-based warnings disabled until proper
validation. Validate on real devices and actual indoor environments.

This change has been committed to GitHub but **has not been built or run on
the Samsung Galaxy S25 Ultra in this environment**; use `flutter analyze`
and the provided unit test to verify it locally.

## Revert

To return to the previous experimental implementation:
`git switch feature/depth-notebook-test` (in a clean working tree).
The original `main` branch was not modified.
