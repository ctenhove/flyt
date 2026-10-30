//
//  ContentView.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

/// The app's main window: paste video URLs and download them concurrently
/// with live progress, each independent of the others. Owns the list of
/// in-flight items and the shared destination/coordinator/history — each
/// item's own fetch → configure → download → complete lifecycle lives in
/// `DownloadItemCard`.
struct ContentView: View {

    /// One card in the list: pairs a freshly-created `YtDlpModel` with the
    /// URL it was started for and a stable identity `ForEach` can diff on.
    private struct Item: Identifiable {
        let id = UUID()
        let urlString: String
        let model: YtDlpModel
        let settings = DownloadItemSettings()
    }

    /// Cards past this count switch the list into a fixed-height scroll
    /// box instead of growing freely — the window has no height cap of its
    /// own (see `FlytApp`'s `.windowResizability`), and each card is tall
    /// enough that even two or three of them can push the window past a
    /// laptop's usable height. Below the threshold there's no ScrollView
    /// at all: one constrained only by `maxHeight` has nothing concrete to
    /// size itself against in this content-driven-sizing window and
    /// collapses to zero height instead of showing anything.
    private static let scrollThreshold = 1
    private static let scrollHeight: CGFloat = 480

    @State private var newURLString: String = ""
    @State private var destinationFolder: URL = Preferences.destinationFolder ?? YtDlpModel.defaultDownloadsDirectory
    @State private var items: [Item] = []

    @State private var coordinator = DownloadCoordinator()
    @State private var historyStore = DownloadHistoryStore()
    @State private var showingHistory = false
    /// Drives the titlebar mark's one-shot completion pulse (see
    /// `MainWindowChrome`) — shared across every card rather than
    /// per-card, since it's a titlebar effect and there's only one titlebar.
    @State private var markPulse = false

    private let dependencyManager: DependencyManager

    /// Debounces auto-fetch so a pasted/dropped link fetches automatically
    /// without spawning a yt-dlp process on every keystroke while a URL is
    /// still being typed out by hand.
    @State private var pendingFetchTask: Task<Void, Never>?

    /// Bumped whenever the app regains focus, so the URL field's clipboard
    /// check (a computed property, otherwise only re-evaluated when some
    /// other `@State` changes) re-runs after switching back from wherever a
    /// YouTube link might have just been copied.
    @State private var clipboardCheckTick = 0

    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            newURLField
            itemsList
            FooterPathRow(destinationFolder: destinationFolder, ytdlpVersion: dependencyManager.installedYtdlpVersion, onChange: chooseDestinationFolder)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 560)
        .background(Color.flytSurface)
        .toolbar {
            MainWindowTitlebar(pulse: markPulse)
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Download history")
            }
        }
        .onChange(of: newURLString) {
            scheduleAutoFetch()
        }
        .onChange(of: destinationFolder) { _, newValue in
            Preferences.destinationFolder = newValue
        }
        .onChange(of: dockFraction) { _, fraction in
            if let fraction {
                DockProgress.update(fraction: fraction)
            } else {
                DockProgress.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            clipboardCheckTick &+= 1
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(store: historyStore, onRedownload: { urlString in
                showingHistory = false
                addItem(urlString: urlString)
            })
        }
    }

    // MARK: List

    /// Overall progress across every download in flight, for the Dock tile —
    /// nil when nothing is downloading, which clears it.
    private var dockFraction: Double? {
        let active = items.map(\.model).filter(\.isDownloading)
        guard !active.isEmpty else { return nil }
        return active.map(\.downloadProgress).reduce(0, +) / Double(active.count)
    }

    /// The URL field's trailing affordance: a one-tap "Paste — youtu.be/…"
    /// when the clipboard holds a YouTube link and the field is empty,
    /// otherwise the plain "⌘V" hint (or nothing, once the user starts typing).
    private var urlFieldTrailing: URLField.Trailing {
        _ = clipboardCheckTick
        guard newURLString.isEmpty else { return .none }
        guard let clipboardURL = ClipboardYouTubeURL.current() else { return .hint }
        return .pasteSuggestion(label: ClipboardYouTubeURL.label(for: clipboardURL)) {
            newURLString = clipboardURL
        }
    }

    @ViewBuilder
    private var newURLField: some View {
        URLField(text: $newURLString, tone: .neutral, trailing: urlFieldTrailing)
            .onSubmit(fetchNow)
        if items.isEmpty {
            IdleDropZone(onDropURL: handleIncomingURL)
        }
    }

    @ViewBuilder
    private var itemsList: some View {
        if items.count > Self.scrollThreshold {
            ScrollView {
                cards
                    .padding(.trailing, 14)
            }
            .frame(height: Self.scrollHeight)
        } else {
            cards
        }
    }

    private var cards: some View {
        VStack(spacing: 14) {
            ForEach(items) { item in
                DownloadItemCard(
                    originalURLString: item.urlString,
                    model: item.model,
                    destinationFolder: destinationFolder,
                    coordinator: coordinator,
                    historyStore: historyStore,
                    onRemove: { remove(item) },
                    onComplete: pulseMark,
                    settings: item.settings
                )
                // Not enough on its own: `itemsList` wraps this same view in
                // a ScrollView once there's more than one item, and that
                // structural change still makes SwiftUI rebuild existing
                // cards, resetting their @State. That's why each card's
                // configuration lives in `item.settings` instead.
                .id(item.id)
            }
        }
    }

    // MARK: Actions

    /// True if `urlString` parses as an http(s) URL with a host — cheap
    /// client-side validation before handing it to yt-dlp, which otherwise
    /// only reports a malformed URL after a slow subprocess round-trip.
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    /// Debounces ~500ms after the last edit before fetching, so a pasted or
    /// dropped link (a single field mutation) fetches automatically without
    /// spawning a yt-dlp process on every keystroke of manual typing.
    private func scheduleAutoFetch() {
        pendingFetchTask?.cancel()
        guard isValidURL(newURLString) else { return }
        let snapshot = newURLString
        pendingFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, snapshot == newURLString else { return }
            fetchNow()
        }
    }

    private func fetchNow() {
        pendingFetchTask?.cancel()
        guard isValidURL(newURLString) else { return }
        addItem(urlString: newURLString)
    }

    private func handleIncomingURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addItem(urlString: trimmed)
    }

    /// Starts a new independent download item and clears the input field
    /// so it's ready for the next link — unlike the single-download
    /// window this replaces, the field represents "what to add next", not
    /// "the current video".
    private func addItem(urlString: String) {
        let model = YtDlpModel(dependencyManager: dependencyManager)
        items.insert(Item(urlString: urlString, model: model), at: 0)
        newURLString = ""
    }

    private func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    private func pulseMark() {
        withAnimation(.easeOut(duration: 0.16)) {
            markPulse = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.16)) {
                markPulse = false
            }
        }
    }

    /// Opens a native folder picker defaulted to `destinationFolder`. Only
    /// affects where downloads started after this point save to — see
    /// `DownloadItemCard.destinationFolder`'s note on why it's a snapshot.
    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url
        }
    }
}
