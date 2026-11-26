# Baseerte AI — Maya Alsuos Update 8

This is the **current AI notebook** for the Flutter Android camera client.
The previous `Maya alsuos.ipynb` (YOLO26n) has been removed from the
`main` branch and replaced with `Maya Alsuos update 8.ipynb`.
Earlier experimental branches are preserved separately for rollback.

## Models and processing

- Object detection: **YOLOv5 Nano**, `yolov5nu.pt`.
- Distance estimation: **Depth Anything V2 Metric Hypersim Small**.
- Depth input size: **256**.
- Experimental calibration: `max(0, 0.444 * depth)`.
- Proximity: vehicles are near below 3m; other objects are near below 1.2m.
- Camera visibility: checks for dark or potentially blocked images.
- Tracking: confirms labels seen in at least 2 of the last 3 frames, with
  a 5-second announcement cooldown and earlier alerts when objects approach.
- API fields include `detections`, `confirmed_detections`, `announcements`,
  `trigger_vibration`, `camera_visibility`, and an annotated JPEG frame.

The Flutter client displays object detections, proximity labels, camera
warnings, and announcement text. **It does not automatically perform
text-to-speech or vibration**; the notebook only sends the flags and text.

## Run the current notebook client

1. Open **`Maya Alsuos update 8.ipynb`** in Google Colab.
2. Run its cells in order, including model downloads and the last cell.
3. Copy the temporary Cloudflare HTTPS API URL printed by the last cell.
4. In Android Studio, run `flutter pub get`, `flutter analyze`,
   `flutter test`, then `flutter run`.
5. Paste the API URL and tap **Connect to notebook**.
6. The phone captures JPEG snapshots roughly every 1.5 seconds (skipping
   overlapping requests) and receives AI results from the notebook server.

The notebook **still requires a running Colab instance** for inference.
It does not include a permanent hosted GPU deployment. The API URL changes
when the tunnel restarts. The current Flutter client does **not** run AI
models on Android, so it does not require TFLite assets.

## Safety and privacy

- Depth readings and 0.444 calibration have **not** been validated on
  physical obstacles. Do not use proximity labels for navigation safety.
- The Cloudflare tunnel exposes the notebook API publicly without
  authentication; only send consented test images. Do not use it as a
  production backend.
- Continuous camera snapshots are **not guaranteed real-time FPS**.
- Model runtime, Flutter build, and phone behavior must still be tested.

The prior notebook and any older AI implementation remain recoverable from
Git history or the backup branch. Removing files from the active Git tree
does **not** erase Git history.
