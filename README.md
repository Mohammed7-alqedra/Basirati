# Baseerte AI — Maya Alsuos Update 10 (split phone + Colab)

## Architecture

**Object detection runs on the Android phone. Depth/distance estimation runs on Google Colab.**

| Part | Technology | Runs where |
| --- | --- | --- |
| Camera + box overlay | Flutter `camera` and CustomPaint | Android |
| Object detection | YOLO11 Nano (`yolo11n.tflite`) via official `ultralytics_yolo` Flutter plugin | Android, on-device |
| Image/box transport | Multipart HTTPS POST | Phone → Colab |
| Depth estimation | Depth Anything V2 Metric Hypersim Small | Google Colab |
| Distance calibration | `max(0, 0.444 * raw_depth)` | Google Colab |
| Endpoint | `POST /estimate-depth` | Google Colab |

The notebook in `main` is **`Maya Alsuos update 10.ipynb`**. The previous
`Maya Alsuos update 8.ipynb` was removed from `main`, but remains in Git
history and the backup branch
`backup/main-before-update10-split-2026-11-28`.

## How it works

1. The Android camera displays a live `CameraPreview()`. Approximately
   every 1.5 seconds (or slower if busy) it captures a JPEG using the
   original `takePicture()` method at `ResolutionPreset.medium`.
2. The phone executes YOLO11 Nano **locally** on the JPEG and obtains
   normalized boxes and object labels. The plugin handles native TFLite
   inference and non-maximum suppression.
3. Flutter immediately draws the boxes and object names over the camera.
   It may initially say **measuring…** next to an object.
4. If Colab is connected, Flutter sends **the same JPEG and those boxes**
   as multipart form data to `/estimate-depth`:
   - `file`: `camera.jpg`.
   - `detections`: JSON array with `label`, `score`, `left`, `top`,
     `right`, `bottom`; the box coordinates are normalized `0..1`.
5. Colab computes a depth map with **Depth Anything V2**, measures depth
   inside each supplied box, applies scale factor `0.444`, and returns
   `detections[*].calibrated_distance_m`.
6. Flutter matches the returned depth to the current local box by **label
   and spatial overlap**, so two chairs cannot be matched only by their
   common class. Distances are updated as fresh responses arrive. Recent
   values expire after 8 seconds; stale camera boxes also expire.

**Important:** YOLO does not run in Colab. The Colab API does not detect
objects itself. When Colab is not connected, phone object detection still
works, but no distance is available.

## Model setup

The phone uses the official Ultralytics release model:

`https://github.com/ultralytics/yolo-flutter-app/releases/download/v0.2.0/yolo11n.tflite`

The `ultralytics_yolo` plugin downloads this model **once on first use**
and caches it on the phone, then runs its inference locally. An internet
connection is required for this **initial model download**. A TFLite
model is not currently committed to this repository. Do not confuse a
model that is *downloaded to the phone* with AI inference performed by a
remote server. For fully offline first installation, bundle a compatible
`yolo11n.tflite` locally and change `OnDeviceObjectDetector.modelUrl`
to its Flutter asset path.

The native plugin is `ultralytics_yolo: 0.6.11`, currently subject to
Ultralytics' **AGPL-3.0** terms; review licensing before distributing the
app commercially.

## Run the depth server in Google Colab

1. Open `Maya Alsuos update 10.ipynb` in Colab.
2. Enable GPU runtime if available and run cells **0 to 14** in order.
   Cells 15–18 are **optional ONNX export** and are not needed to serve
   requests.
3. Copy the **API PUBLIC URL** printed in cell 14, for example
   `https://<temporary>.trycloudflare.com`.
4. Visit `<PUBLIC URL>/health`. The JSON should include
   `"yolo_in_colab": false` and a `depth_model` entry.
5. In the Android app, paste **only the base URL**, not
   `/estimate-depth` or `/health`. Tap **Start camera**.

Colab needs to remain running; the Cloudflare URL is temporary. The
notebook resizes uploaded images so their longest dimension is 640 px,
which can change distance estimates from Update 8 even with the same
calibration. Re-measure real distances and calibrate before trusting any
values.

## Run the Android app

From PowerShell in the repository:

```powershell
git switch main
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run
```

To test phone YOLO without Colab, leave the depth URL blank and press
**Start camera**. The app does not send photos to Colab in that mode.

Source files:
- `lib/on_device_detector.dart`: on-phone YOLO11 model, bounding boxes,
  detection matching and temporary distance attachment.
- `lib/colab_depth_client.dart`: depth-only multipart HTTP contract.
- `lib/detection_overlay.dart`: visual labels and boxes.
- `lib/main.dart`: Flutter camera and request orchestration.
- `Maya Alsuos update 10.ipynb`: only Depth Anything V2 AI on Colab.

## Safety, privacy and limits

- The current **0.444 calibration is experimental** and was not validated
  for obstacle avoidance. This assistive prototype is **not a navigation
  safety system**.
- The camera preview is live, but YOLO predictions update on captured
  photos; the app does **not** perform continuous per-frame tracking.
  Bounding boxes can lag or differ from the preview's crop/FOV.
- Distances update only as the Colab server responds; 8-second safeguards
  prevent keeping stale distance labels indefinitely.
- When connected to Colab, the app uploads camera JPEGs plus detected
  labels/positions. The temporary Cloudflare tunnel has no authentication;
  use only consented test scenes, not sensitive images.
- The notebook includes an optional ONNX export for the **depth model**.
  That does not make depth run on the phone.
- Flutter, Android model downloading, frame-to-box alignment and actual
  device speed require hands-on testing. No device build was executed by
  the automated repository changes.
