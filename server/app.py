"""FastAPI inference service for Maya alsuos.ipynb, without Colab.

Models: YOLO26n + Depth Anything V2 Metric Hypersim Small, original PyTorch
checkpoint. The distance formula is experimental and not safety validated.
"""
from __future__ import annotations

import base64
import logging
import os
import secrets
import sys
import threading
import time
from contextlib import asynccontextmanager

import cv2
import numpy as np
import torch
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from ultralytics import YOLO

# The official depth repository is cloned by the Dockerfile.
sys.path.insert(0, os.environ.get("DEPTH_CODE_DIR", "/opt/Depth-Anything-V2/metric_depth"))
from depth_anything_v2.dpt import DepthAnythingV2

CHECKPOINT = os.environ.get(
    "DEPTH_CHECKPOINT", "/opt/models/depth_anything_v2_metric_hypersim_vits.pth"
)
MAX_IMAGE_BYTES = int(os.environ.get("MAX_IMAGE_BYTES", "5000000"))
ACCESS_KEY = os.environ.get("BASIRATI_API_KEY", "")
INPUT_SIZE = 518
INSET_RATIO = 0.20
SCALE_FACTOR = 1.05
OFFSET = -0.10

log = logging.getLogger("basirati")
processing_lock = threading.Lock()
yolo_model = None
depth_model = None
device = None
total_frames = 0
total_processing_time = 0.0


def load_models():
    global yolo_model, depth_model, device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    log.warning("Loading Maya AI models on %s", device)
    model = DepthAnythingV2(
        encoder="vits", features=64, out_channels=[48, 96, 192, 384], max_depth=20
    )
    model.load_state_dict(torch.load(CHECKPOINT, map_location="cpu", weights_only=True), strict=True)
    depth_model = model.to(device).eval()
    yolo_model = YOLO(os.environ.get("YOLO_WEIGHTS", "/app/yolo26n.pt"))
    log.warning("Both models loaded")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if len(ACCESS_KEY) < 24:
        raise RuntimeError("Set BASIRATI_API_KEY to a random value of at least 24 characters.")
    load_models()
    yield


app = FastAPI(title="Basirati AI — Maya models", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok", "models": ["yolo26n", "depth_anything_v2_metric_hypersim_small"]}


def detect_objects(frame: np.ndarray):
    prediction = yolo_model.predict(source=frame, conf=0.25, device=str(device), verbose=False)
    detections = []
    for result in prediction:
        for box in result.boxes:
            x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
            class_id = int(box.cls[0])
            detections.append({
                "object": str(result.names[class_id]),
                "confidence": float(box.conf[0]),
                "bbox": [int(x1), int(y1), int(x2), int(y2)],
            })
    return detections


def calculate_median_depth(depth_map: np.ndarray, bbox: list[int]):
    height, width = depth_map.shape[:2]
    x1, y1, x2, y2 = map(int, bbox)
    x1, x2 = max(0, min(x1, width)), max(0, min(x2, width))
    y1, y2 = max(0, min(y1, height)), max(0, min(y2, height))
    if x2 <= x1 or y2 <= y1:
        return None

    inset_x = int((x2 - x1) * INSET_RATIO)
    inset_y = int((y2 - y1) * INSET_RATIO)
    region = depth_map[y1 + inset_y:y2 - inset_y, x1 + inset_x:x2 - inset_x]
    if region.size == 0:
        region = depth_map[y1:y2, x1:x2]
    valid = region[np.isfinite(region) & (region > 0)]
    if valid.size == 0:
        return None
    return float(np.median(valid))


def infer(frame: np.ndarray):
    global total_frames, total_processing_time
    if not processing_lock.acquire(blocking=False):
        return None
    try:
        started = time.perf_counter()
        objects = detect_objects(frame)

        # This matches Maya's notebook: one full-image depth map per frame.
        with torch.inference_mode():
            depth_map = np.asarray(depth_model.infer_image(frame, INPUT_SIZE), dtype=np.float32)

        results = []
        output_frame = frame.copy()
        for entry in objects:
            raw = calculate_median_depth(depth_map, entry["bbox"])
            distance = max(0.0, SCALE_FACTOR * raw + OFFSET) if raw is not None else None
            results.append({
                **entry,
                "raw_depth_m": raw,
                "calibrated_distance_m": distance,
            })
            x1, y1, x2, y2 = entry["bbox"]
            label = entry["object"]
            if distance is not None:
                label += f": {distance:.2f} m"
            cv2.rectangle(output_frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(
                output_frame, label, (x1, max(25, y1 - 10)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2,
            )
        elapsed = time.perf_counter() - started
        total_frames += 1
        total_processing_time += elapsed

        success, encoded = cv2.imencode(".jpg", output_frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        if not success:
            raise RuntimeError("Failed encoding annotated image")
        return {
            "status": "processed",
            "detections": results,
            "output_frame": base64.b64encode(encoded.tobytes()).decode("ascii"),
            "processing_time": elapsed,
            "processing_fps": 1.0 / elapsed if elapsed > 0 else 0.0,
            "average_fps": total_frames / total_processing_time if total_processing_time > 0 else 0.0,
            "total_frames_processed": total_frames,
        }
    finally:
        processing_lock.release()


@app.post("/process-frame")
async def process_camera_frame(
    file: UploadFile = File(...),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
):
    if not x_api_key or not secrets.compare_digest(x_api_key, ACCESS_KEY):
        raise HTTPException(status_code=401, detail="Unauthorized")
    if file.content_type not in ("image/jpeg", "image/png", "application/octet-stream"):
        raise HTTPException(status_code=415, detail="JPEG or PNG image required")
    data = await file.read(MAX_IMAGE_BYTES + 1)
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image missing or exceeds upload limit")

    frame = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise HTTPException(status_code=400, detail="Invalid image")
    if frame.shape[0] > 2500 or frame.shape[1] > 2500:
        raise HTTPException(status_code=413, detail="Image dimensions too large")

    try:
        result = await run_in_threadpool(infer, frame)
    except Exception:
        log.exception("Frame inference failed")
        raise HTTPException(status_code=500, detail="Frame processing failed")
    if result is None:
        return {"status": "dropped", "message": "Server busy"}
    return result
