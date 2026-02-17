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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/monitor.log"
}

urlencode() {
    jq -nr --arg value "$1" '$value|@uri'
}

refresh_plex() {
    local video_path="$1"
    local parent_dir=$(dirname "$video_path")

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

log "=========================================="
log "SubSync Queue Monitor v1.1"
log "=========================================="
log "Queue dir: $QUEUE_DIR"
[ -n "$PLEX_URL" ] && log "Plex URL: $PLEX_URL" || log "Plex integration: disabled"
log "Starting monitor loop..."

mkdir -p "$QUEUE_DIR" 2>/dev/null || true

inotifywait -m -e create,moved_to --format '%f' "$QUEUE_DIR" 2>/dev/null | while read filename; do
    if [[ ! "$filename" =~ \.json$ ]]; then
        continue
    fi

    QUEUE_FILE="$QUEUE_DIR/$filename"
    sleep 0.5

    log "Processing: $filename"

    VIDEO=$(jq -r '.video // empty' "$QUEUE_FILE" 2>/dev/null || echo "")
    SUBTITLE=$(jq -r '.subtitle // empty' "$QUEUE_FILE" 2>/dev/null || echo "")
    SUB_LANG=$(jq -r '.subtitle_lang // empty' "$QUEUE_FILE" 2>/dev/null || echo "")
    VID_LANG=$(jq -r '.video_lang // empty' "$QUEUE_FILE" 2>/dev/null || echo "")

    if [ -z "$VIDEO" ] || [ -z "$SUBTITLE" ]; then
        log "ERROR: Invalid JSON format: $filename"
        rm -f "$QUEUE_FILE"
        continue
    fi

    log "Video: $(basename "$VIDEO")"
    log "Subtitle: $(basename "$SUBTITLE")"
    log "Language: $SUB_LANG -> $VID_LANG"
    log "Running subsync..."

    if /scripts/subsync-wrapper.sh \
        "$VIDEO" \
        "$SUBTITLE" \
        "${SUB_LANG}" \
        "${VID_LANG}" >> "$LOG_DIR/subsync-exec.log" 2>&1; then
        log "OK SubSync completed successfully"
        refresh_plex "$VIDEO"
    else
        EXIT_CODE=$?
        log "ERROR SubSync failed (code: $EXIT_CODE)"
    fi

    rm -f "$QUEUE_FILE"
    log "=========================================="
done

log "Monitor stopped"
