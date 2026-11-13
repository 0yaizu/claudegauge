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
                    Text(model.fiveHour.text).frame(height: Self.lineHeight)
                    Text(model.weekly.text).frame(height: Self.lineHeight)
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: Self.textWidth, alignment: .trailing)
            }
        }
        .frame(height: Self.height)
    }
}
