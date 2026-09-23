#!/bin/bash
# SubSync Queue Monitor - container version with Plex integration

set -euo pipefail

QUEUE_DIR="${QUEUE_DIR:-/queue}"
LOG_DIR="${LOG_DIR:-/logs}"

# Plex integration
PLEX_URL="${PLEX_URL:-}"
PLEX_TOKEN="${PLEX_TOKEN:-}"
PLEX_SECTION_SHOWS="${PLEX_SECTION_SHOWS:-1}"
PLEX_SECTION_MOVIES="${PLEX_SECTION_MOVIES:-2}"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

urlencode() {
    jq -nr --arg value "$1" '$value|@uri'
}

refresh_plex() {
    local video_path="$1"
    local parent_dir
    parent_dir=$(dirname "$video_path")

    if [ -z "$PLEX_URL" ] || [ -z "$PLEX_TOKEN" ]; then
        log "WARN Plex integration disabled (missing PLEX_URL or PLEX_TOKEN)"
        return 0
    fi

    # Determine section ID based on path
    local section_id
    if [[ "$video_path" == *"/shows/"* ]] || [[ "$video_path" == *"/tv/"* ]]; then
        section_id="$PLEX_SECTION_SHOWS"
    else
        section_id="$PLEX_SECTION_MOVIES"
    fi

    log "Refreshing Plex (section $section_id): $parent_dir"

    # URL encode the path
    local encoded_path
    encoded_path=$(urlencode "$parent_dir")

    if wget -q -O /dev/null \
        --header="X-Plex-Token: $PLEX_TOKEN" \
        "${PLEX_URL}/library/sections/${section_id}/refresh?path=${encoded_path}"; then
        log "OK Plex refresh completed"
    else
        log "WARN Plex refresh failed (check token and URL)"
    fi
}

process_queue_file() {
    local queue_file="$1"
    local filename
    filename=$(basename "$queue_file")

    if [ ! -f "$queue_file" ]; then
        return 0
    fi

    log "Processing: $filename"

    local video subtitle sub_lang vid_lang
    video=$(jq -r '.video // empty' "$queue_file" 2>/dev/null || echo "")
    subtitle=$(jq -r '.subtitle // empty' "$queue_file" 2>/dev/null || echo "")
    sub_lang=$(jq -r '.subtitle_lang // empty' "$queue_file" 2>/dev/null || echo "")
    vid_lang=$(jq -r '.video_lang // empty' "$queue_file" 2>/dev/null || echo "")

    if [ -z "$video" ] || [ -z "$subtitle" ]; then
        log "ERROR: Invalid JSON format: $filename"
        rm -f "$queue_file"
        return 0
    fi

    log "Video: $(basename "$video")"
    log "Subtitle: $(basename "$subtitle")"
    log "Language: $sub_lang -> $vid_lang"
    log "Running subsync..."

    if /scripts/subsync-wrapper.sh \
        "$video" \
        "$subtitle" \
        "${sub_lang}" \
        "${vid_lang}" >> "$LOG_DIR/subsync-exec.log" 2>&1; then
        log "OK SubSync completed successfully"
        refresh_plex "$video"
    else
        local exit_code=$?
        log "ERROR SubSync failed (code: $exit_code)"
    fi

    rm -f "$queue_file"
    log "=========================================="
}

log "=========================================="
log "SubSync Queue Monitor v1.1"
log "=========================================="
log "Queue dir: $QUEUE_DIR"
[ -n "$PLEX_URL" ] && log "Plex URL: $PLEX_URL" || log "Plex integration: disabled"
log "Starting monitor loop..."

mkdir -p "$QUEUE_DIR"
if [ ! -r "$QUEUE_DIR" ] || [ ! -w "$QUEUE_DIR" ] || [ ! -w "$LOG_DIR" ]; then
    log "ERROR Queue and log directories must be readable and writable"
    exit 1
fi

# Rescan after each event and timeout. A job created between the scan and
# inotify registration is picked up by the next scan instead of being stranded.
while true; do
    for queue_file in "$QUEUE_DIR"/*.json; do
        [ -e "$queue_file" ] || continue
        process_queue_file "$queue_file"
    done

    if inotifywait -q -t 10 -e create,moved_to "$QUEUE_DIR" >/dev/null 2>&1; then
        sleep 0.5
    else
        sleep 1
    fi
done
