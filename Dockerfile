# syntax=docker/dockerfile:1

# Build stage: SubSync 0.17 with its native extension (gizmo), compiled against FFmpeg 5 and PocketSphinx.
# SubSync's setup.py links all FFmpeg libraries; --as-needed keeps only the four gizmo uses.
FROM python:3.11-slim-bookworm@sha256:94a8fee35252d06ab75856f15f12c7bae67b10e8a6da93c7fded82b2610926cd AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git pkg-config \
        libavcodec-dev libavdevice-dev libavfilter-dev libavformat-dev libavutil-dev libswresample-dev libswscale-dev \
        libpocketsphinx-dev libsphinxbase-dev \
    && rm -rf /var/lib/apt/lists/*

# The tag and the commit it must point to: a moved tag fails the build instead of changing the code.
ARG SUBSYNC_VERSION=0.17
ARG SUBSYNC_COMMIT=be5390d00ff475b6543eb0140c7e65b34317d95b
COPY patches/ /patches/
RUN git clone --depth 1 --branch "${SUBSYNC_VERSION}" https://github.com/sc0ty/subsync.git /src \
    && test "$(git -C /src rev-parse HEAD)" = "${SUBSYNC_COMMIT}" \
    && git -C /src apply /patches/subsync-0.17-ffmpeg5.patch \
    && python -m venv /opt/venv \
    && LDFLAGS="-Wl,--as-needed" /opt/venv/bin/pip install --no-cache-dir -r /src/requirements.txt /src \
    && find /opt/venv -name '*.so' -exec strip --strip-unneeded {} + \
    && find /opt/venv -name '__pycache__' -prune -exec rm -rf {} + \
    && /opt/venv/bin/pip uninstall -y pip pybind11

# Runtime stage: only the shared libraries the extension links against, the virtualenv, and the bridge.
FROM python:3.11-slim-bookworm@sha256:94a8fee35252d06ab75856f15f12c7bae67b10e8a6da93c7fded82b2610926cd

RUN apt-get update && apt-get install -y --no-install-recommends \
        libavcodec59 libavformat59 libavutil57 libswresample4 libpocketsphinx3 libsphinxbase3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/venv /opt/venv
COPY bridge.py /app/bridge.py

# HOME holds SubSync's settings and downloaded speech models; mount a volume there to keep them.
# It is world-writable so the container can run as any PUID:PGID.
ENV PATH=/opt/venv/bin:$PATH \
    HOME=/cache \
    PYTHONUNBUFFERED=1
RUN mkdir -p /queue /logs /cache && chmod 1777 /cache \
    && python -c "import gizmo" && subsync --version

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --start-interval=2s --retries=3 \
    CMD ["python3", "/app/bridge.py", "--health"]

CMD ["python3", "/app/bridge.py"]

LABEL org.opencontainers.image.title="Bazarr SubSync Bridge" \
      org.opencontainers.image.description="Queue-based Bazarr post-processing bridge for SubSync subtitle alignment with optional Plex refresh" \
      org.opencontainers.image.source="https://github.com/kopiezzo/bazarr-subsync-bridge" \
      org.opencontainers.image.licenses="GPL-3.0-only"
