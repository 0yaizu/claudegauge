import Foundation

/// メニューバーの表示内容。入れ子ドーナツ (外側が 5h、内側が weekly) と、右側に縦に並べる %。
///
///     ◎  28%   ← 5h
///        17%   ← weekly
public struct MenuBarModel: Equatable, Sendable {
    public struct Ring: Equatable, Sendable {
        public let text: String
        public let fraction: Double
        public let level: UsageLevel

        init(_ usage: WindowUsage?) {
            let gauge = usage.map { GaugeValue(utilization: $0.utilization) } ?? .empty
            text = usage.map { DisplayFormatter.percent($0.utilization) } ?? DisplayFormatter.percent(.nan)
            fraction = gauge.fraction
            level = gauge.level
        }
    }

    public let fiveHour: Ring
    public let weekly: Ring

    public static func make(snapshot: UsageSnapshot?) -> MenuBarModel {
        MenuBarModel(fiveHour: Ring(snapshot?.fiveHour), weekly: Ring(snapshot?.weekly))
    }
}
