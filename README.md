# MustDo

Native macOS app for stashing things you want to **do**, **watch**, **read**, and **listen** to later.

## Lists

- **Must Do** — plain text todos with rich notes.
- **Must Watch** — paste a YouTube / Twitter URL and download for offline viewing with bundled `yt-dlp`, or drag in local video files. Plays inline with AVPlayer.
- **Must Read** — paste web URLs (rendered in WKWebView), drag PDFs (PDFKit), or EPUBs (in-app reader). MOBI / other docs open in the default app.
- **Must Listen** — paste podcast RSS URLs (parsed into an episode list) or audio URLs, or drag local audio files. Plays inline.

## Requirements

- macOS 26+
- Xcode 26+

## First-time setup

Before the first build, fetch `yt-dlp` (the binary is not committed to git):

```bash
./scripts/fetch_ytdlp.sh
```

This downloads `yt-dlp_macos` into `MustDo/Resources/yt-dlp`. Re-run it occasionally to update.

## Build & run

```bash
open MustDo.xcodeproj
```

Build & run from Xcode. To build from the command line:

```bash
xcodebuild -project MustDo.xcodeproj -scheme MustDo -configuration Debug build
```

## Data storage

- SwiftData store lives in `~/Library/Application Support/com.moerdowo.MustDo/`.
- Imported / downloaded media lives under `…/com.moerdowo.MustDo/Media/`.
- Deleting an item removes its stored files.
