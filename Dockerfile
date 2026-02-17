# Dockerfile - SubSync Container
# Combined: subsync (subtitle sync) + monitor (queue watcher)
# Base: Python 3.11 on Debian Bullseye for FFmpeg compatibility

FROM python:3.11-slim-bullseye

# Metadata
LABEL maintainer="bazarr-subsync-bridge maintainers"
LABEL description="SubSync container for Bazarr integration with queue monitoring"
LABEL version="1.0"

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    SUBSYNC_VERSION=0.17

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build dependencies
    build-essential \
    pkg-config \
    cmake \
    git \
    # FFmpeg and libraries
    ffmpeg \
    libavcodec-dev \
    libavdevice-dev \
    libavfilter-dev \
    libavformat-dev \
    libavutil-dev \
    libswresample-dev \
    libswscale-dev \
    # Speech recognition
    libsphinxbase-dev \
    pocketsphinx \
    libpocketsphinx-dev \
    # Monitoring tools
    inotify-tools \
    jq \
    wget \
    # Process manager
    supervisor \
    # Other tools
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install pybind11 for subsync compilation
RUN pip install --no-cache-dir pybind11

# Download and install subsync
WORKDIR /tmp/subsync
RUN git clone --depth 1 --branch ${SUBSYNC_VERSION} https://github.com/sc0ty/subsync.git . && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir . && \
    cd / && rm -rf /tmp/subsync

# Create working directories
RUN mkdir -p /scripts /queue /logs /media

# Copy scripts
COPY subsync-wrapper.sh /scripts/subsync-wrapper.sh
COPY subsync-monitor.sh /scripts/subsync-monitor.sh
RUN chmod +x /scripts/*.sh

# Create supervisord config
RUN mkdir -p /etc/supervisor/conf.d

COPY supervisord.conf /etc/supervisor/conf.d/subsync.conf

# Create runtime user/group (default 1000:1000)
ARG PUID=1000
ARG PGID=1000
RUN groupadd -g ${PGID} subsync && \
    useradd -u ${PUID} -g ${PGID} -m -s /bin/bash subsync && \
    chown -R subsync:subsync /scripts /queue /logs /media

USER subsync

# Healthcheck - verify monitor process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f inotifywait > /dev/null || exit 1

# Start supervisord to manage monitor process
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/subsync.conf"]
