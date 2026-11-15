import AppKit
import SwiftUI

/// Lamp's colours: neutral system chrome and one accent, the amber of the lamp's light. Green and red only mean a
/// state. See docs/design.
enum Palette {
    /// Fills: a dot, a progress bar, the hold ring.
    static let amber = Color(red: 0.949, green: 0.647, blue: 0.255)
    /// Amber as text or a thin line: darker on light surfaces, so it stays readable.
    static let amberInk = dynamic(dark: 0xF2A541, light: 0x9A5806)
    static let ok = dynamic(dark: 0x8FC46A, light: 0x3F7D2A)
    static let bad = dynamic(dark: 0xEF6B5A, light: 0xC4321F)
    static let off = dynamic(dark: 0x5D5F64, light: 0xA3A4A8)
    /// The well a log sits in.
    static let inset = dynamic(dark: 0x0F1012, light: 0xEAEAE7)

    static let nsAmber = NSColor(srgbRed: 0.949, green: 0.647, blue: 0.255, alpha: 1)
    static let nsBad = NSColor(srgbRed: 0.937, green: 0.420, blue: 0.353, alpha: 1)

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Times as the panel writes them.
enum Clockface {
    /// "1:42", "12:05", "1:02:03".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }
}

/// The ring that fills while the user holds an action that changes something.
struct HoldRing: View {
    var progress: Double
    var tint: Color
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size - 3, height: size - 3)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Runs `action` only after the user holds for `duration`; the label shows the progress. VoiceOver activates it
/// directly, since its label already says that it changes something.
struct HoldToRun<Label: View>: View {
    var duration: Double = 0.8
    var enabled = true
    let action: () -> Void
    @ViewBuilder let label: (_ progress: Double) -> Label
    @State private var progress = 0.0

    var body: some View {
        label(progress)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 24) {
                guard enabled else { return }
                action()
                progress = 0
            } onPressingChanged: { pressing in
                guard enabled else { return }
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }
}
