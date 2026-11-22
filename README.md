# Basirati — Maya alsuos notebook only

This Android project has been replaced with a Flutter camera client for the
uploaded notebook `Maya alsuos.ipynb`.

**The notebook runs two Python AI models online:** YOLO26n for object detection
and Depth Anything V2 Metric Hypersim Small for distance estimation. The
notebook also applies experimental calibration `max(0, 1.05 * depth - 0.10)`.

The old YOLO11n and stairs TFLite models, label files, detector classes,
volume-button hooks, and on-device inference dependencies were removed.
**There is no specialized stairs model in this notebook.** The notebook does
not contain a self-contained Android TFLite model. Inference is online.

## Run

1. Open `Maya alsuos.ipynb` in Google Colab.
2. Run all cells in order. Download required pretrained weights as scripted.
3. Keep the Colab runtime and the last cell's FastAPI server running.
4. Copy the temporary `API PUBLIC URL` printed by the last cell.
5. Run `flutter pub get`, `flutter analyze`, `flutter test`, then
   `flutter run` from Android Studio.
6. In the app, paste the public HTTPS URL and tap **Connect to notebook**.
7. The app takes camera snapshots, uploads them as JPEG to
   `POST /process-frame`, and shows the returned annotated results.

The public URL changes when the Cloudflare tunnel restarts, so reconnect
using the new one.

## Limitations

This client needs internet and a running Colab instance. Captures are taken
about every 1.5 seconds when not already processing; this is not guaranteed
real-time frame-rate inference.

The notebook exposes a temporary **public, unauthenticated** endpoint;
camera photos transit over the network. Do not upload sensitive scenes or
other people's images without consent. Deploy with authentication and
appropriate security controls before general use.

Distances are **not validated** for visually impaired navigation. Do not use
them to make safety or obstacle-avoidance decisions.

Old models have been deleted from the current Git tree, but Git commit
history may still contain earlier files.
