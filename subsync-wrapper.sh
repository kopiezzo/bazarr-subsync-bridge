#!/bin/bash
# SubSync Wrapper Script dla Bazarr Custom Post-Processing
#
# Ten skrypt jest wywoływany przez Bazarr po pobraniu napisów
# i automatycznie synchronizuje je z video używając subsync

set -euo pipefail

# Konfiguracja
SUBSYNC_LOG_LEVEL="${SUBSYNC_LOG_LEVEL:-1}"  # 0=error, 1=info, 2=debug, 3=verbose
SUBSYNC_EFFORT="${SUBSYNC_EFFORT:-0.5}"       # 0.0-1.0, im wyższe tym dokładniejsze ale wolniejsze
SUBSYNC_MAX_WINDOW="${SUBSYNC_MAX_WINDOW:-600}"  # Maksymalna korekta w sekundach (10 min)
SUBSYNC_MIN_CORRELATION="${SUBSYNC_MIN_CORRELATION:-0.5}"  # Minimalna korelacja dla sukcesu

# Funkcja logowania
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Sprawdzenie argumentów
if [ $# -lt 2 ]; then
    log_error "Wymagane argumenty: VIDEO_FILE SUBTITLE_FILE [SUBTITLE_LANG] [VIDEO_LANG]"
    exit 1
fi

VIDEO_FILE="$1"
SUBTITLE_FILE="$2"
SUBTITLE_LANG="${3:-}"
VIDEO_LANG="${4:-}"

# Walidacja plików
if [ ! -f "$VIDEO_FILE" ]; then
    log_error "Plik video nie istnieje: $VIDEO_FILE"
    exit 1
fi

if [ ! -f "$SUBTITLE_FILE" ]; then
    log_error "Plik napisów nie istnieje: $SUBTITLE_FILE"
    exit 1
fi

# Sprawdzenie rozmiaru pliku napisów (jeśli puste, nie ma co synchronizować)
if [ ! -s "$SUBTITLE_FILE" ]; then
    log_error "Plik napisów jest pusty: $SUBTITLE_FILE"
    exit 1
fi

log "========================================="
log "SubSync - Automatyczna synchronizacja napisów"
log "========================================="
log "Video: $VIDEO_FILE"
log "Napisy: $SUBTITLE_FILE"
log "Język napisów: ${SUBTITLE_LANG:-auto}"
log "Język video: ${VIDEO_LANG:-auto}"
log "Effort: $SUBSYNC_EFFORT"
log "Max window: ${SUBSYNC_MAX_WINDOW}s"
log "========================================="

# Backup oryginalnych napisów
BACKUP_FILE="${SUBTITLE_FILE}.bak-$(date +%s)"
cp "$SUBTITLE_FILE" "$BACKUP_FILE"
log "Backup utworzony: $BACKUP_FILE"

# Plik tymczasowy dla wyjścia (subsync nie pozwala nadpisać pliku wejściowego)
# Używamy katalogu tymczasowego aby uniknąć problemów z pattern
TEMP_DIR="/tmp/subsync_$$"
mkdir -p "$TEMP_DIR"
TEMP_OUTPUT="$TEMP_DIR/output.srt"
rm -f "$TEMP_OUTPUT"

# Budowanie komendy subsync
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

# Uwaga: Opcje --sub-lang i --ref-lang są NIEDOSTĘPNE w subsync 0.17.0 (bug)
# Subsync automatycznie wykryje język z plików

# Wykonanie synchronizacji
log "Uruchamianie subsync..."
log "Komenda: ${SUBSYNC_CMD[*]}"

if "${SUBSYNC_CMD[@]}"; then
    log "✓ Synchronizacja zakończona sukcesem!"

    # Kopiowanie pliku tymczasowego do właściwego miejsca
    if [ -f "$TEMP_OUTPUT" ]; then
        mv "$TEMP_OUTPUT" "$SUBTITLE_FILE"
        log "Napisy zostały zsynchronizowane: $SUBTITLE_FILE"

        # Usunięcie backupu po sukcesie (opcjonalne)
        if [ "${SUBSYNC_KEEP_BACKUP:-0}" = "0" ]; then
            rm -f "$BACKUP_FILE"
            log "Backup usunięty (SUBSYNC_KEEP_BACKUP=0)"
        else
            log "Backup zachowany: $BACKUP_FILE"
        fi

        rm -rf "$TEMP_DIR"

        exit 0
    else
        log_error "✗ Plik wyjściowy nie został utworzony: $TEMP_OUTPUT"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    EXIT_CODE=$?
    log_error "✗ Synchronizacja nie powiodła się (kod: $EXIT_CODE)"
    log_error "Przywracanie oryginalnych napisów z backupu..."

    # Przywrócenie backupu w przypadku błędu
    mv "$BACKUP_FILE" "$SUBTITLE_FILE"
    rm -rf "$TEMP_DIR"
    log_error "Oryginalne napisy przywrócone"

    exit $EXIT_CODE
fi
