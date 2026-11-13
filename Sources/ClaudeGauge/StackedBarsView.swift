import ClaudeGaugeCore
import SwiftUI

/// 横棒 2 本。上が 5h、下が weekly。左から右へ塗る。
struct StackedBarsView: View {
    let fiveHour: MenuBarModel.Ring
    let weekly: MenuBarModel.Ring
    /// 空の部分 (トラック) に使う文字色。
    let ink: Color

    /// 全長が短いと、低い使用率 (3% と 17% など) の差が見えなくなる。
    private static let width: CGFloat = 32
    private static let barHeight: CGFloat = 5
    private static let gap: CGFloat = 3

    var body: some View {
        VStack(spacing: Self.gap) {
            bar(fiveHour)
            bar(weekly)
        }
    }

    private func bar(_ ring: MenuBarModel.Ring) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ink.opacity(0.25))
            // 塗りは「全長の棒を、使用率の長さで切り取る」。
            // 短い塗りを最小幅で止めると、低い使用率がどれも同じ点に見えてしまう。
            if ring.fraction > 0 {
                Capsule()
                    .fill(ring.level.color)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: Self.width * ring.fraction)
                    }
            }
        }
        .frame(width: Self.width, height: Self.barHeight)
    }
}
