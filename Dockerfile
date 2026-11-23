FROM pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PORT=7860 \
    YOLO_WEIGHTS=/app/yolo26n.pt \
    DEPTH_CHECKPOINT=/opt/models/depth_anything_v2_metric_hypersim_vits.pth

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY server/requirements.txt /app/server/requirements.txt
RUN pip install --no-cache-dir -r /app/server/requirements.txt

# Official Depth Anything V2 source, retaining the notebook's PyTorch model.
RUN git clone --depth 1 https://github.com/DepthAnything/Depth-Anything-V2.git /opt/Depth-Anything-V2

# Download the same pretrained Hypersim Small depth checkpoint from the notebook.
RUN mkdir -p /opt/models && python -c "import urllib.request; urllib.request.urlretrieve('https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-Hypersim-Small/resolve/main/depth_anything_v2_metric_hypersim_vits.pth', '/opt/models/depth_anything_v2_metric_hypersim_vits.pth')"

# Cache the YOLO26n checkpoint in the image for faster server startups.
RUN python -c "from ultralytics import YOLO; YOLO('yolo26n.pt')"
COPY server /app/server

EXPOSE 7860
CMD ["sh", "-c", "exec uvicorn server.app:app --host 0.0.0.0 --port ${PORT:-7860} --workers 1"]
