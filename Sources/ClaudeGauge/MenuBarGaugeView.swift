import ClaudeGaugeCore
import SwiftUI

/// メニューバーに出す絵そのもの。絵 (ドーナツまたは横棒) と、右側に縦に並べた % (上が 5h、下が weekly)。
///
///     ◎  28%        ▬▬▬▬  28%
///        17%        ▬▬    17%
struct MenuBarGaugeView: View {
    let model: MenuBarModel
    let style: MenuBarStyle
    let showsText: Bool
    let ink: Color

    /// 桁数が変わってもメニューバーの幅が揺れないよう、"100%" が入る幅を常に確保する。
    private static let textWidth: CGFloat = 25
    /// グラフと % の列の間隔。% は右寄せの固定幅なので、桁数が少ないと見た目の間隔はこれより広くなる。
    private static let graphTextSpacing: CGFloat = 2
    static let height: CGFloat = 20

    var body: some View {
        HStack(spacing: Self.graphTextSpacing) {
            switch style {
            case .donut:
                NestedDonutView(outer: model.fiveHour, inner: model.weekly, ink: ink)
            case .bar:
                StackedBarsView(fiveHour: model.fiveHour, weekly: model.weekly, ink: ink)
            }
            if showsText {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(model.fiveHour.text)
                    Text(model.weekly.text)
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
