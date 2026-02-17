#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <video> <subtitle> [subtitle_lang_code3] [video_lang_code3]" >&2
    exit 1
fi

VIDEO_FILE="$1"
SUBTITLE_FILE="$2"
SUBTITLE_LANG="${3:-}"
VIDEO_LANG="${4:-}"

# Directory shared with subsync container as /queue.
QUEUE_DIR="${SUBSYNC_QUEUE_DIR:-/config/scripts/subsync-queue}"

mkdir -p "$QUEUE_DIR"
JOB_FILE="$QUEUE_DIR/job-$(date +%s)-$$.json"

python3 - "$VIDEO_FILE" "$SUBTITLE_FILE" "$SUBTITLE_LANG" "$VIDEO_LANG" "$JOB_FILE" <<'PY'
import json
import os
import sys

video, subtitle, subtitle_lang, video_lang, job_file = sys.argv[1:6]

payload = {
    "video": video,
    "subtitle": subtitle,
}

if subtitle_lang:
    payload["subtitle_lang"] = subtitle_lang
if video_lang:
    payload["video_lang"] = video_lang

tmp_file = f"{job_file}.tmp"
with open(tmp_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False)

os.replace(tmp_file, job_file)
PY

echo "[subsync-postprocess] queued: $JOB_FILE" >&2
