#!/bin/bash
# Bazarr post-processing hook: queue a SubSync job for Bazarr SubSync Bridge.
# Bazarr command: bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <video> <subtitle> [subtitle_lang_code3] [video_lang_code3]" >&2
    exit 1
fi

# Directory shared with the bridge container as /queue
QUEUE_DIR="${SUBSYNC_QUEUE_DIR:-/config/scripts/subsync-queue}"
mkdir -p "$QUEUE_DIR"

# The job is written as *.json.tmp and renamed, so the bridge never reads a partial file.
python3 - "$QUEUE_DIR" "$@" <<'PY'
import json, os, sys, time

queue, video, subtitle = sys.argv[1:4]
langs = (sys.argv[4:6] + ["", ""])[:2]
job = {"video": video, "subtitle": subtitle}
for key, value in zip(("subtitle_lang", "video_lang"), langs):
    if value:
        job[key] = value

path = os.path.join(queue, f"job-{time.time_ns()}-{os.getpid()}.json")
with open(path + ".tmp", "w", encoding="utf-8") as f:
    json.dump(job, f, ensure_ascii=False)
os.replace(path + ".tmp", path)
print(f"[subsync-postprocess] queued: {path}", file=sys.stderr)
PY
