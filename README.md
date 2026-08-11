# flyt

*FetchLight for YouTube.*

flyt is a lightweight, native macOS app for downloading YouTube videos, written entirely in SwiftUI. It wraps [yt-dlp](https://github.com/yt-dlp/yt-dlp) and bundles [ffmpeg](https://ffmpeg.org) so it works out of the box — paste a link, pick a format, download.

## Opening it the first time

flyt isn't notarized, so macOS Gatekeeper will block it as coming from an unidentified developer the first time you open it. To allow it:

1. Try to open flyt (double-click it, or launch it from Xcode). You'll get a dialog saying it can't be opened.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the Security section — you'll see a message that flyt was blocked. Click **Open Anyway**.
4. Confirm in the dialog that appears.

You only need to do this once. After that, flyt opens normally like any other app.

On first launch, flyt also downloads and verifies a small `ffmpeg` binary it needs for merging video and audio — this happens automatically in the background and only once.

## Using the app

1. **Paste or drop a link.** Copy a YouTube URL and paste it into the field, or drag a link straight into the window. flyt fetches the video's title, thumbnail, and available formats automatically.
2. **Check the format.** By default flyt picks the best available resolution and audio track. Click **Options** to expand the picker if you want to choose a different resolution, container (MP4/WebM/MKV), audio track, or switch to audio-only.
3. **Rename it, if you want.** The filename field defaults to the video's title; edit it directly, or click **Reset to video title** to go back to the default.
4. **Download.** Click Download (or press ⌘Return). Progress, speed, and time remaining show live; Cancel stops it at any point.
5. **Find your file.** Once it finishes, click **Show in Finder** to jump straight to it, or **Download another** to start over. Downloads land in `~/Downloads/flyt` by default — click **Change…** near the URL field to pick a different folder.

flyt keeps its bundled `yt-dlp` up to date automatically (checked once a day in the background), so it keeps working as YouTube changes without you needing to update the app.

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

## Third-party components

flyt bundles two external tools rather than requiring you to install them separately:

- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** — [Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) (public domain). No attribution required, included here as a courtesy.
- **[ffmpeg](https://ffmpeg.org)** — GPL-licensed build (includes `libx264`/`libx265`), from [Martin Riedl's FFmpeg build server](https://ffmpeg.martin-riedl.de). Source is available from [ffmpeg.org](https://ffmpeg.org/download.html) and the build server linked above. See ffmpeg's [GPL license](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html).

## License

GPL-3.0 — see [LICENSE](LICENSE).
