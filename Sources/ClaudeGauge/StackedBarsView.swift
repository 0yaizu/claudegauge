import ClaudeGaugeCore
import SwiftUI

struct StackedBarsView: View {
    let fiveHour: MenuBarModel.Ring
    let weekly: MenuBarModel.Ring
    let ink: Color
    let rowHeight: CGFloat

    private static let width: CGFloat = 32
    private static let barHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            bar(fiveHour).frame(height: rowHeight)
            bar(weekly).frame(height: rowHeight)
        }
    }

    private func bar(_ ring: MenuBarModel.Ring) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ink.opacity(0.25))
            if ring.fraction > 0 {
                Capsule()
                    .fill(ring.level.color)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: Self.width * ring.fraction)
                    }
            }
        }
        .frame(width: Self.width, height: Self.barHeight)
    }
}
