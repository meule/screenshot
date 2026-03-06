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

  log "Uploading $(basename "$file") -> $url"

  if aws s3 cp "$file" "s3://$BUCKET/$key" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --content-type "image/${file##*.}" \
    --quiet 2>>"$LOG"; then

    log "Uploaded: $url"
    terminal-notifier -title "Screenshot uploaded" -message "$url" -open "$url" -sound Glass
  else
    log "FAILED to upload $(basename "$file")"
    osascript -e 'display notification "Upload failed — check log" with title "Screenshot upload error" sound name "Basso"'
  fi
}

# Record startup time — ignore files that existed before we started
START_TIME=$(date +%s)

log "Watcher started (PID $$)"

# Use process substitution so the while loop runs in the main shell
while IFS= read -r -d '' file; do
  base=$(basename "$file")

  # Skip dotfiles and non-image files
  [[ "$base" == .* ]] && continue
  [[ "$base" != *.png && "$base" != *.jpg && "$base" != *.jpeg ]] && continue

  # Skip files that existed before the watcher started
  file_mtime=$(stat -f%m "$file" 2>/dev/null || echo 0)
  [[ "$file_mtime" -lt "$START_TIME" ]] && continue

  # Deduplicate: skip if marker exists (from a prior fswatch event for same file)
  marker="$DEDUP_DIR/$base"
  [[ -f "$marker" ]] && continue
  touch "$marker"

  # Generate URL and copy to clipboard immediately
  ext="${base##*.}"
  rand=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c4)
  key="$(date '+%Y/%m/%d/%H%M%S')-${rand}.${ext}"
  url="https://${BUCKET}.s3.${REGION}.amazonaws.com/${key}"
  echo -n "$url" | pbcopy

  # Upload in background
  upload "$file" "$key" "$url" &
done < <(fswatch -0 --latency 0.1 "$WATCH_DIR")
