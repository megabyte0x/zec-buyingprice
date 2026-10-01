import SwiftUI
import AppKit

// The palette is shared by every surface so the notebook reads as one workspace.
enum LabTheme {
    static let burgundy = Color(red: 121 / 255, green: 13 / 255, blue: 22 / 255)
    static let parchment = Color(red: 229 / 255, green: 211 / 255, blue: 175 / 255)
    static let ivory = Color(red: 245 / 255, green: 239 / 255, blue: 225 / 255)
    static let blue = Color(red: 174 / 255, green: 196 / 255, blue: 212 / 255)
    static let ink = Color(red: 46 / 255, green: 39 / 255, blue: 37 / 255)
    static let muted = Color(red: 106 / 255, green: 93 / 255, blue: 79 / 255)
    static let line = ink.opacity(0.14)
    static let paper = Color(red: 252 / 255, green: 248 / 255, blue: 240 / 255)
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

struct LabButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? LabTheme.ivory : LabTheme.ink)
            .background(primary ? LabTheme.burgundy : LabTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : LabTheme.line))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LabCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(LabTheme.muted)
    }
}

struct LabField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content.textFieldStyle(.plain).font(.system(size: 13))
                .padding(12).background(LabTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(LabTheme.line))
        }
    }
}

struct ScientistArtwork: View {
    private static let artwork = Bundle.module.url(forResource: "scientist", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        if let artwork = Self.artwork {
            Image(nsImage: artwork).resizable().scaledToFill()
                .accessibilityLabel("An illustrated scientist in mechanical goggles studying a Zcash coin in his laboratory")
        }
    }
}

extension View {
    func labPanel() -> some View {
        background(LabTheme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LabTheme.line))
    }
}
