import ClaudeGaugeCore
import SwiftUI

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .caution: .yellow
        case .critical: .red
        }
    }
}

/// 横棒グラフ。塗りは幅を変えず、位置 (transform) をずらして伸び縮みさせる。
struct UsageBar: View {
    let fraction: Double
    let level: UsageLevel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 強めの ease-out。値が更新されたときの反応を速く見せる。
    private static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Rectangle()
                    .fill(level.color)
                    .offset(x: -(1 - fraction) * proxy.size.width)
                    .animation(reduceMotion ? nil : Self.easeOut, value: fraction)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}
