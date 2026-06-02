#!/bin/bash
# Fetch the yt-dlp macOS binary into MustDo/Resources/yt-dlp.
# Re-run periodically to update.
set -euo pipefail

DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/MustDo/Resources"
DEST="$DEST_DIR/yt-dlp"

mkdir -p "$DEST_DIR"

URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

echo "Downloading yt-dlp_macos to $DEST ..."
curl -L --fail --progress-bar -o "$DEST" "$URL"
chmod +x "$DEST"

echo "Done."
"$DEST" --version || true
