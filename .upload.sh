#!/bin/bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

WATCH_DIR="$HOME/Screenshots"
BUCKET="kostya-screenshots-eu"
REGION="eu-central-1"
PROFILE="kostya"
LOG="$WATCH_DIR/.upload.log"
DEDUP_DIR="$WATCH_DIR/.uploaded"
mkdir -p "$DEDUP_DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

upload() {
  local file="$1"
  local key="$2"
  local url="$3"

  # Wait for file write to complete (poll size for up to 3s)
  local prev_size=-1 curr_size
  for _ in 1 2 3 4 5 6; do
    curr_size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    [[ "$curr_size" -gt 0 && "$curr_size" == "$prev_size" ]] && break
    prev_size=$curr_size
    sleep 0.5
  done

  log "Uploading ${file##*/} -> $url"

  if aws s3 cp "$file" "s3://$BUCKET/$key" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --content-type "image/${file##*.}" \
    --quiet 2>>"$LOG"; then

    log "Uploaded: $url"
    terminal-notifier -title "Screenshot uploaded" -message "$url" -open "$url" -sound Glass
  else
    log "FAILED to upload ${file##*/}"
    osascript -e 'display notification "Upload failed — check log" with title "Screenshot upload error" sound name "Basso"'
  fi
}

# Mark all existing files as already seen so we don't upload them on start
for f in "$WATCH_DIR"/*.png "$WATCH_DIR"/*.jpg "$WATCH_DIR"/*.jpeg; do
  [[ -f "$f" ]] && touch "$DEDUP_DIR/${f##*/}"
done

log "Watcher started (PID $$)"

# Poll every 0.2s — avoids FSEvents coalescing delay (~1-2s)
while true; do
  for file in "$WATCH_DIR"/*.png "$WATCH_DIR"/*.jpg "$WATCH_DIR"/*.jpeg; do
    [[ -f "$file" ]] || continue
    base="${file##*/}"
    [[ "$base" == .* ]] && continue

    marker="$DEDUP_DIR/$base"
    [[ -f "$marker" ]] && continue
    touch "$marker"

    # Generate URL and copy to clipboard immediately
    ext="${base##*.}"
    key="$(date '+%Y/%m/%d/%H%M%S')-$(printf '%04x' $RANDOM).${ext}"
    url="https://${BUCKET}.s3.${REGION}.amazonaws.com/${key}"
    echo -n "$url" | pbcopy

    upload "$file" "$key" "$url" &
  done
  sleep 0.2
done
