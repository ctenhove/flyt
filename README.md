# flyt

*FetchLight for YouTube.*

flyt is a lightweight, native macOS app for downloading YouTube videos, written entirely in SwiftUI. It wraps [yt-dlp](https://github.com/yt-dlp/yt-dlp) and bundles [ffmpeg](https://ffmpeg.org) so it works out of the box — paste a link, pick a format, download.

## Features

- Paste, drop, or auto-detect a YouTube URL and fetch its metadata
- Choose resolution, video container (MP4/WebM/MKV), and audio track from whatever formats the video actually offers
- Audio-only downloads
- Live download progress with speed and ETA
- Custom filenames, with automatic sanitization and collision-safe naming
- Self-updating `yt-dlp` (checked once a day in the background, installs a newer release automatically) so the app keeps working as YouTube changes, without an app update
- A bundled, pinned `ffmpeg` for merging separate video/audio streams — installed once on first launch, no Homebrew or external dependency required

## Requirements

- macOS 14.6+
- Xcode 26+ (uses Swift's `@Observable`/`@concurrent` and other recent language features)

## Building

```
open flyt.xcodeproj
```

Build and run the `flyt` scheme (⌘R). No package dependencies to resolve, no environment setup beyond Xcode — `yt-dlp` ships bundled as a resource in `Resources/`, and `ffmpeg` is downloaded and verified automatically on first launch.

## Project structure

```
flyt/
├── FlytApp.swift              — app entry point
├── ContentView.swift          — main window: owns state, composes per-state views
├── SetupView.swift            — first-launch screen (installs ffmpeg)
├── YtDlpModel.swift           — wraps the yt-dlp binary: fetch metadata, download, cancel
├── DependencyManager.swift    — installs/verifies ffmpeg; checks for yt-dlp updates
├── Views/                     — one file per main-window state/component
├── DesignSystem/              — shared type styles, the brand mark, layout helpers
├── Support/                   — pure helpers (format selection, filename rules, error copy)
└── Assets.xcassets/           — app icon + light/dark colour tokens

Resources/
└── yt-dlp_macos               — bundled yt-dlp binary (fallback; self-updates in place)
```

## Design

flyt's visual design follows a handoff bundle (tokens, states, and motion specs) covering the main window, first-launch setup screen, and brand mark. Not yet implemented: the menu-bar popover, system notifications, a Preferences window, and playlist support — these exist in the design handoff but need backend work beyond what `YtDlpModel` currently supports (single-video fetch/download/cancel only).

## License

No license file yet — all rights reserved by default until one is added.
