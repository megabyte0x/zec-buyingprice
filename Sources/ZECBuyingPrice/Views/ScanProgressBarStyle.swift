import SwiftUI

struct ScanProgressBarStyle: ProgressViewStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LabTheme.line)
                Capsule().fill(LabTheme.burgundy)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
        .accessibilityLabel("Mainnet scan progress")
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(1))))
    }
}
