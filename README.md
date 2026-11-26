# Baseerte AI — Maya Alsuos Update 8

Flutter Android camera client for Maya's **YOLOv5 Nano (`yolov5nu.pt`)**
and **Depth Anything V2 Metric Hypersim Small**. Both AI models still
run on the remote notebook GPU, **not on the Android phone**.

## Live camera responsiveness update

Previously, the Flutter app took a full photo every 1.5 seconds and replaced
the camera preview with a static annotated image when the API responded. This
made movement appear frozen even when the server's processing time was low.

The current implementation:

- Keeps **`CameraPreview()` visible at all times** in portrait orientation.
- Uses **`startImageStream()`** to obtain camera frames without stopping preview.
- Sends at most one selected frame every **500 ms**, and skips incoming frames
  while a request is processing; this is a throttle, not a guaranteed 2 FPS.
- Downscales frames to at most **640 pixels** and encodes JPEG in a separate
  Dart isolate with the `image` package.
- Overlays bounding boxes, object names, and experimental distances using
  Flutter **`Stack` + `CustomPainter`**.
- Expires stale boxes after 2 seconds and displays observed AI processing time
  and total capture + conversion + network latency.
- Sends `include_image=false` as a multipart field so the updated API skips
  base64 image encoding and returns compact detection metadata.
- Retains the prior response format for other clients: the notebook returns
  `output_frame` as before if `include_image` is omitted or true.

Camera format conversion supports Android 3-plane YUV420 and packed NV21
plus iOS BGRA. The portrait rear-camera rotation is based on sensor
orientation. **Overlay alignment and runtime performance must be checked on
the actual Android device**, because camera drivers and preview crops vary.

## Run

1. Pull the updated `main` branch in Android Studio.
2. Run `flutter pub get`, `flutter analyze`, and `flutter test`.
3. Open the updated **`Maya Alsuos update 8.ipynb`** in Google Colab
   (not an older copy already open in a browser).
4. Run all notebook cells in order, including the updated FastAPI cell.
5. Run the final server cell; copy its Cloudflare HTTPS `API PUBLIC URL`.
6. Run `flutter run`, paste the URL, and tap **Connect to notebook**.
7. Keep Colab running while testing. The app shows a live preview with
   asynchronously updated detection boxes and text labels.

## AI models and alerts (unchanged)

- Object detection: YOLOv5 Nano.
- Metric depth: Depth Anything V2 Hypersim Small.
- Depth input size: 256.
- Experimental distance scale: `max(0, 0.444 * raw_depth)`.
- Proximity thresholds: vehicles near below 3 m; other objects below 1.2 m.
- Visibility checks for dark or blocked camera images.
- Multi-frame announcement confirmation (2 of last 3), 5-second cooldown.
- Flutter shows announcement text and danger indicators but does **not**
  automatically speak or vibrate.

## Limitations

- This is **not a permanent GPU server**. The notebook still requires Colab
  and a changing temporary tunnel URL.
- The API tunnel is public and unauthenticated. Only use consented test images.
- The camera can render smoothly while AI updates arrive more slowly.
  Performance depends on encoding, upload, inference, and network conditions.
- Detection boxes may be delayed or slightly misaligned on particular camera
  hardware, especially when the stream and preview have different crops.
- Distance calibration is **unvalidated** and must not be used as reliable
  obstacle detection or navigation guidance for visually impaired users.

Earlier versions are recoverable from Git history and backup branches.
