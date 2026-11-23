# Basirati AI — offline version of Maya's notebook

This experimental Android version uses **the models in `Maya alsuos.ipynb`**,
running on the phone instead of in Google Colab:

1. **YOLO26n** for object detection, via Ultralytics' official Flutter LiteRT plugin.
2. **Depth Anything V2 Metric Hypersim Small** for per-pixel metric indoor
   depth, via the LiteRT/TFLite export of the *same pretrained Hypersim Small
   checkpoint* found at
   https://huggingface.co/litert-community/Depth-Anything-V2-Metric-Hypersim-Small

The notebook's distance postprocessing is retained:
- Read the median of positive finite depths in the central 60% of a detected
  object's bounding box.
- Apply `max(0, 1.05 * raw_depth - 0.10)` to get an experimental estimate.

**The notebook contains two separate AI models**, not one combined model.
The old YOLO11n and stairs detector are **not** used by this branch.
No Colab, public API, server, or cloud inference is used.

## First use — prepare before university

1. Connect the Android phone to **Wi-Fi**, with approximately 200 MB free
   storage for models and installation overhead.
2. In Android Studio, switch to `feature/maya-models-offline`.
3. Run `flutter pub get`, `flutter analyze`, `flutter test`, then
   `flutter run` (use `flutter run --profile` for realistic performance).
4. Tap **Prepare / Start offline models**. Wait for the 99 MB metric-depth
   download and the YOLO26n model initialization/download to finish.
5. Verify that the screen says **Both models loaded locally** and reports
   object detections and approximate distances.
6. Close the app, enable **Airplane mode**, reopen the app, tap **Prepare /
   Start offline models**, and verify that detection continues. Do this
   **before** relying on the university demo. Do not clear the app's storage.

On later launches, downloaded model files are cached inside the phone.
Android OS and app data deletion may remove them; reinstallations can
require a fresh download. First-time setup requires internet, but
**no Colab session is needed at any time**.

## Current limitations

- **This branch is a prototype and has not been compiled or tested on a
  physical Android device.** It must not be advertised as a finished offline
  implementation until Flutter builds and phone tests pass.
- The mobile depth export accepts a fixed 518x518 **center crop**. The
  notebook's Python `infer_image` uses aspect-preserving resizing of the
  full image. This can change results, and objects outside the center crop
  have no depth estimate. We have *not* established numerical parity with
  the notebook.
- Object detection and depth estimate must be checked against real, tape-
  measured reference distances in the actual university environment.
  The notebook's 1.05 scale and -0.10 offset are not validated for your
  phone. **Do not use estimated distances for navigation or obstacle safety.**
- This prototype takes one camera JPEG at a time (starting about every 3s,
  skipping overlapping work), not guaranteed real-time video. Heavy model
  computation may temporarily affect responsiveness.
- Ultralytics model downloads use its official model cache; depth uses app
  support storage. If either download fails, retry while connected to Wi-Fi.
- Confirm the licenses and redistribution requirements of the model and
  Ultralytics Flutter plugin before publication.

The original notebook remains in the repository. The prior Colab-based app
is available on the unchanged `main` branch until this is tested.
