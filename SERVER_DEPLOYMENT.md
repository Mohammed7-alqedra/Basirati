# Hosted Basirati AI — deploy Maya's models without Colab

This branch prepares an independently running server with **the same two
models** from `Maya alsuos.ipynb`:

- Ultralytics `yolo26n.pt` (object detection).
- Depth Anything V2 Metric Hypersim Small checkpoint
  `depth_anything_v2_metric_hypersim_vits.pth`.

The depth model runs once per frame using its original Python
`infer_image(frame, 518)`; object distances are the median of valid pixels
from the central 60% of each bounding box, followed by
`max(0, 1.05 * raw_depth - 0.10)`. These figures are not validated for
navigation.

## System

- Android Flutter takes JPEG camera photos (not heavy phone-side inference).
- A separately deployed **HTTPS GPU server** accepts `POST /process-frame`
  and returns annotations, objects, and experimental distances.
- No Google Colab, laptop, temporary Cloudflare tunnel, or phone-side model
  download is required after server deployment.

## Deployment

The repository includes a root `Dockerfile` for CUDA/PyTorch GPU hosting,
plus `server/app.py` and `server/requirements.txt`. Use a provider that
supports **custom Docker images, NVIDIA GPUs, HTTPS, long-running web
services**, and at least one server replica. GPU server billing and image
build/download time may be significant.

1. Create a hosted GPU web service from this GitHub branch.
2. Use the root `Dockerfile`; expose HTTP port `7860` behind provider HTTPS.
3. Add an environment secret named `BASIRATI_API_KEY`: at least 24 random
   characters. Do **not** commit it into GitHub or embed it in the APK.
4. Wait for the image build (installs the original depth code and downloads
   both trained models) and for startup model loading.
5. Verify `https://YOUR-SERVICE/health` returns `{"status":"ok", ...}`.
6. Test `POST /process-frame` with a JPEG multipart form field called
   `file` and HTTP header `X-API-Key: YOUR_SECRET`.
7. On Android, use the permanent HTTPS server URL (and access key for this
   initial demonstration). The mobile app keeps the same API response
   contract as the notebook and does **not** run inference locally.

For an app build with a prefilled server address (NOT an embedded secret):

```powershell
flutter run --dart-define=BASIRATI_API_URL=https://YOUR-SERVICE
```

Or paste the URL into the app manually. The app includes an access-key field
for **controlled testing**; users must provide that key. A distributed public
app must instead use individual user authentication and server-side
authorization, not a single shared API key.

### Security and reliability

- Only send camera photos with the user's consent. Frames leave the phone.
- `BASIRATI_API_KEY` is required; requests without the correct key receive
  HTTP 401. Use HTTPS and keep credentials server-side where possible.
- Only one inference runs concurrently per service replica; frames are
  dropped when the replica is busy, matching the notebook's anti-lag behavior.
  For multiple simultaneous users, add horizontally scaled GPU replicas and
  a suitable gateway/authentication design.
- Choose a service that **does not sleep** if immediate response is critical,
  otherwise account for cold starts and model-loading delay.
- Performance and accuracy have not been benchmarked on the chosen host.
  Experimental depth distances must **never** be used as reliable
  obstacle-navigation warnings.
- The model and Python package licenses need review before public release.

## Server health and API

`GET /health` — readiness status after models load.

`POST /process-frame` — multipart JPEG/PNG `file` +
`X-API-Key` request header; returns `status`, `detections`,
`output_frame` (base64 JPEG), and processing metrics. Maximum upload
size defaults to 5 MB.

## Status

**GitHub contains deployment-ready source, not an actual running server.**
Deployment requires your account with a hosting provider and a selected GPU
instance. The APK, backend container build, model downloads, and live
inference are not yet tested on a real host.
