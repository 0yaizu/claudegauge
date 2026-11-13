import ClaudeGaugeCore
import SwiftUI

/// 入れ子ドーナツ。外側が 5h、内側が weekly。12 時の位置から時計回りに塗る。
struct NestedDonutView: View {
    let outer: MenuBarModel.Ring
    let inner: MenuBarModel.Ring
    /// 空の輪 (トラック) に使う文字色。
    let ink: Color

    static let size: CGFloat = 18
    private static let lineWidth: CGFloat = 2.4
    /// 外側の輪と内側の輪の間の隙間。
    private static let gap: CGFloat = 1.2

    var body: some View {
        ZStack {
            ring(outer, inset: Self.lineWidth / 2)
            ring(inner, inset: Self.lineWidth * 1.5 + Self.gap)
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// `inset` は枠の端から、輪の中心線までの距離。
    private func ring(_ ring: MenuBarModel.Ring, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(ink.opacity(0.25), lineWidth: Self.lineWidth)
            // 0% のときに丸い端点だけが残らないよう、塗りがあるときだけ描く。
            if ring.fraction > 0 {
                Circle()
                    .trim(from: 0, to: ring.fraction)
                    .stroke(ring.level.color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(inset)
    }
}
