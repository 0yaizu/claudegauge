import AppKit
import ClaudeGaugeCore
import SwiftUI

struct MenuBarGaugeView: View {
    let model: MenuBarModel
    let style: MenuBarStyle
    let showsText: Bool
    let ink: Color

    private static let textWidth: CGFloat = 25
    private static let graphTextSpacing: CGFloat = 2
    static let height: CGFloat = 20
    private static let lineHeight: CGFloat = 11
    private static let fontSize: CGFloat = 8.5
    private static let capHeight = NSFont.systemFont(ofSize: fontSize, weight: .semibold).capHeight

    var body: some View {
        HStack(spacing: Self.graphTextSpacing) {
            switch style {
            case .donut:
                NestedDonutView(outer: model.fiveHour, inner: model.weekly, ink: ink)
            case .bar:
                StackedBarsView(fiveHour: model.fiveHour, weekly: model.weekly, ink: ink, rowHeight: Self.lineHeight)
            }
            if showsText {
                VStack(alignment: .trailing, spacing: 0) {
                    digitsRow(model.fiveHour.text)
                    digitsRow(model.weekly.text)
                }
                .font(.system(size: Self.fontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: Self.textWidth, alignment: .trailing)
            }
        }
        .frame(height: Self.height)
    }

    private func digitsRow(_ text: String) -> some View {
        Text(text)
            .alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] - Self.capHeight / 2 }
            .frame(height: Self.lineHeight)
    }
}
