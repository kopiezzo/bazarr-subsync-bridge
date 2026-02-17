#!/bin/bash
# SubSync Wrapper Script for Bazarr Custom Post-Processing
#
# This script is called by Bazarr after subtitle download
# and synchronizes subtitles with the video using subsync

set -euo pipefail

# Configuration
SUBSYNC_LOG_LEVEL="${SUBSYNC_LOG_LEVEL:-1}"  # 0=error, 1=info, 2=debug, 3=verbose
SUBSYNC_EFFORT="${SUBSYNC_EFFORT:-0.5}"       # 0.0-1.0, higher is more accurate but slower
SUBSYNC_MAX_WINDOW="${SUBSYNC_MAX_WINDOW:-600}"  # Maximum correction window in seconds (10 min)
SUBSYNC_MIN_CORRELATION="${SUBSYNC_MIN_CORRELATION:-0.5}"  # Minimum correlation threshold for success

# Logging helpers
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Validate arguments
if [ $# -lt 2 ]; then
    log_error "Required arguments: VIDEO_FILE SUBTITLE_FILE [SUBTITLE_LANG] [VIDEO_LANG]"
    exit 1
fi

VIDEO_FILE="$1"
SUBTITLE_FILE="$2"
SUBTITLE_LANG="${3:-}"
VIDEO_LANG="${4:-}"

# Validate files
if [ ! -f "$VIDEO_FILE" ]; then
    log_error "Video file does not exist: $VIDEO_FILE"
    exit 1
fi

if [ ! -f "$SUBTITLE_FILE" ]; then
    log_error "Subtitle file does not exist: $SUBTITLE_FILE"
    exit 1
fi

# Check subtitle file size (skip if empty)
if [ ! -s "$SUBTITLE_FILE" ]; then
    log_error "Subtitle file is empty: $SUBTITLE_FILE"
    exit 1
fi

log "========================================="
log "SubSync - Automatic subtitle synchronization"
log "========================================="
log "Video: $VIDEO_FILE"
log "Subtitle: $SUBTITLE_FILE"
log "Subtitle language: ${SUBTITLE_LANG:-auto}"
log "Video language: ${VIDEO_LANG:-auto}"
log "Effort: $SUBSYNC_EFFORT"
log "Max window: ${SUBSYNC_MAX_WINDOW}s"
log "========================================="

# Backup original subtitle file
BACKUP_FILE="${SUBTITLE_FILE}.bak-$(date +%s)"
cp "$SUBTITLE_FILE" "$BACKUP_FILE"
log "Backup created: $BACKUP_FILE"

# Temporary output file (subsync cannot overwrite input file directly)
# Use a temporary directory to avoid output pattern issues
TEMP_DIR="/tmp/subsync_$$"
mkdir -p "$TEMP_DIR"
TEMP_OUTPUT="$TEMP_DIR/output.srt"
rm -f "$TEMP_OUTPUT"

# Build subsync command
SUBSYNC_CMD=(
    subsync --cli sync
    --sub "$SUBTITLE_FILE"
    --ref "$VIDEO_FILE"
    --out "$TEMP_OUTPUT"
    "--effort=$SUBSYNC_EFFORT"
    "--window-size=$SUBSYNC_MAX_WINDOW"
    "--min-correlation=$SUBSYNC_MIN_CORRELATION"
    "--verbose=$SUBSYNC_LOG_LEVEL"
)

# Note: --sub-lang and --ref-lang are unavailable in subsync 0.17.0 (known issue)
# Subsync auto-detects language from files

# Execute synchronization
log "Running subsync..."
log "Command: ${SUBSYNC_CMD[*]}"

if "${SUBSYNC_CMD[@]}"; then
    log "OK Synchronization completed successfully"

    # Move temporary output to target subtitle path
    if [ -f "$TEMP_OUTPUT" ]; then
        mv "$TEMP_OUTPUT" "$SUBTITLE_FILE"
        log "Subtitles synchronized: $SUBTITLE_FILE"

        # Remove backup after success (optional)
        if [ "${SUBSYNC_KEEP_BACKUP:-0}" = "0" ]; then
            rm -f "$BACKUP_FILE"
            log "Backup removed (SUBSYNC_KEEP_BACKUP=0)"
        else
            log "Backup kept: $BACKUP_FILE"
        fi

        rm -rf "$TEMP_DIR"

        exit 0
    else
        log_error "ERROR Output file was not created: $TEMP_OUTPUT"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    EXIT_CODE=$?
    log_error "ERROR Synchronization failed (code: $EXIT_CODE)"
    log_error "Restoring original subtitles from backup..."

    # Restore backup on failure
    mv "$BACKUP_FILE" "$SUBTITLE_FILE"
    rm -rf "$TEMP_DIR"
    log_error "Original subtitles restored"

    exit $EXIT_CODE
fi
