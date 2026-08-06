//
//  SetupView.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import SwiftUI

/// First-launch screen shown while the ffmpeg dependency is checked and
/// downloaded — a visual restyle only (design handoff: "flyt Setup
/// Window"). The state machine, transitions, and copy are unchanged from
/// the original implementation; only the presentation is new.
struct SetupView: View {
    let state: DependencyManager.SetupState
    /// Download completion in 0...1; nil shows an indeterminate track.
    let downloadProgress: Double?

    var body: some View {
        Group {
            switch state {
            case .checking:
                // Deliberately not wrapped in `.animation` — the handoff
                // calls for an instant swap here, since `checking` often
                // lasts only a few frames and a crossfade would be more
                // noticeable than the state itself.
                ProgressFrame(label: "Checking dependencies…", progress: nil, caption: nil, statusSpacing: 11, isReady: false)
            case .downloading:
                ProgressFrame(
                    label: "Downloading ffmpeg…",
                    progress: downloadProgress,
                    caption: "This happens once, on first launch.",
                    statusSpacing: 9,
                    isReady: false
                )
            case .ready:
                // Lasts ~200ms before the app hands off to the main
                // window — the mark's completion pulse is what actually
                // carries this moment, not the label.
                ProgressFrame(label: "Ready", progress: 1, caption: nil, statusSpacing: 9, isReady: true)
            case .failed(let message):
                FailedView(message: message)
            }
        }
        .frame(width: 400, height: 250)
        .background(Color.flytSurface)
    }
}

/// The shared layout for checking/downloading/ready: brand block on top,
/// a progress track + label underneath. One frame for all three so the
/// near-instant `checking` pass doesn't flash a different layout.
private struct ProgressFrame: View {
    var label: String
    /// nil = indeterminate track.
    var progress: Double?
    var caption: String?
    var statusSpacing: CGFloat
    var isReady: Bool

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                SetupMark(isReady: isReady)
                    .frame(width: 46, height: 46)
                Text("flyt")
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.76)
                    .foregroundStyle(.flytSky)
            }
            VStack(spacing: statusSpacing) {
                ProgressTrack(progress: progress, isReady: isReady)
                labelRow
                if let caption {
                    Text(caption)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.flytFaintText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .frame(width: 236)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var labelRow: some View {
        if let progress, !isReady {
            HStack {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.flytBodyTextSecondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.flytSkyHover)
                    .monospacedDigit()
            }
        } else {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isReady ? Color.flytFaintText : Color.flytBodyTextSecondary)
        }
    }
}

/// The progress track: determinate (a known fraction), indeterminate (a
/// sliding bar, shown until a fraction is known), or the "ready" resting
/// state — full and Sky-tinted rather than gray.
private struct ProgressTrack: View {
    var progress: Double?
    var isReady: Bool

    @State private var indeterminatePhase = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isReady ? Color.flytSky.opacity(0.2) : Color.flytProgressRail)
                if let progress {
                    Capsule()
                        .fill(Color.flytSky)
                        .frame(width: proxy.size.width * progress)
                } else {
                    Capsule()
                        .fill(Color.flytSky)
                        .frame(width: proxy.size.width * 0.3)
                        .offset(x: indeterminatePhase ? proxy.size.width : -proxy.size.width * 0.3)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                indeterminatePhase = true
                            }
                        }
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .animation(.linear(duration: 0.2), value: progress)
    }
}

/// The Downplay mark, animated: a continuous "breathing" loop while
/// checking/downloading (triangle drop + bar pulse, looping), settling
/// into a single completion pulse the moment `isReady` becomes true —
/// the app's one sanctioned mark animation (see brand brief, Motion),
/// also used on main-window download completion.
///
/// Drawn from the same 100-unit master geometry as the app's other mark
/// usage (`FlytMark`), but as two independently animatable shape layers
/// rather than one static `Canvas` draw — `FlytMark` itself stays
/// untouched since its titlebar/button/drop-zone usages don't need that.
private struct SetupMark: View {
    var isReady: Bool

    @State private var isLooping = false
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            MarkTriangleShape()
                .fill(Color.flytSky)
                .offset(y: triangleOffset)
                .opacity(triangleOpacity)
            MarkBarShape()
                .fill(Color.flytSky)
                .opacity(isReady ? 1 : 0.85)
                .scaleEffect(x: barScale, y: 1, anchor: .center)
        }
        .onAppear {
            guard !isReady else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isLooping = true
            }
        }
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            withAnimation(.easeOut(duration: 0.16)) { isPulsing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeOut(duration: 0.16)) { isPulsing = false }
            }
        }
    }

    private var triangleOffset: CGFloat {
        isReady ? 0 : (isLooping ? 0 : -5)
    }

    private var triangleOpacity: Double {
        isReady ? 1 : (isLooping ? 1 : 0.55)
    }

    private var barScale: CGFloat {
        isReady ? (isPulsing ? 1.14 : 1) : (isLooping ? 1.14 : 1)
    }
}

/// The mark's triangle, normalized to the same 100-unit canvas as the
/// brand brief's master geometry (`M29 31 H71 L50 66 Z`) so it scales
/// cleanly to any frame size.
private struct MarkTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.29 * rect.width, y: rect.minY + 0.31 * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + 0.71 * rect.width, y: rect.minY + 0.31 * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + 0.50 * rect.width, y: rect.minY + 0.66 * rect.height))
        path.closeSubpath()
        return path
    }
}

/// The mark's landing bar (`rect x30 y74 w40 h8 rx4` on the same canvas).
private struct MarkBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX + 0.30 * rect.width
        let y = rect.minY + 0.74 * rect.height
        let width = 0.40 * rect.width
        let height = 0.08 * rect.height
        let radius = 0.04 * rect.width
        return Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }
}

/// The failed state: deliberately different from the progress frame —
/// left-aligned, no mark, Coral used only on the warning glyph. The tone
/// target is "a one-time setup step didn't work," not an app crash, so
/// there's no red fill and no destructive-styled button.
private struct FailedView: View {
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.flytCoral)
                Text("Setup failed")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.32)
                    .foregroundStyle(.flytSlate)
            }

            errorPanel

            Text("ffmpeg is required and couldn't be installed. The app will now quit.")
                .font(.system(size: 12.5))
                .foregroundStyle(.flytBodyTextSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // The handoff's "Setup help" link is dropped: there's nowhere
            // for it to go yet (no help/support surface in the app), and
            // the handoff explicitly says the layout works without it.
            HStack {
                Spacer()
                QuitButton()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Scrolls internally rather than growing the window if `message` is
    /// unusually long, per the handoff — this is a fixed 400×250 window.
    private var errorPanel: some View {
        ScrollView {
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.flytBodyTextSecondary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Color.flytPanel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct QuitButton: View {
    @State private var isHovering = false

    var body: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.flytInvertedText)
                .padding(.horizontal, 20)
                .frame(height: 32)
                .background(
                    // Hover reuses flytBodyText's hex rather than adding a
                    // fifth narrow token for a single button's hover state;
                    // it happens to be exactly the handoff's #334155.
                    isHovering ? Color.flytBodyText : Color.flytInvertedSurface,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
