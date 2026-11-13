import Foundation

/// 使用率から、描画に使う塗り割合 (0...1) と警告レベルを決める。
/// 棒グラフ・メニューバーのドーナツで共通。異常値 (NaN など) は空・通常として扱う。
public struct GaugeValue: Equatable, Sendable {
    public let fraction: Double
    public let level: UsageLevel

    public init(utilization: Double) {
        guard utilization.isFinite else {
            fraction = 0
            level = .normal
            return
        }
        fraction = min(max(utilization / 100, 0), 1)
        level = UsageLevel(percent: utilization)
    }

    /// 枠が無い (まだ取得できていない・Pro の 5h など) 場合。
    public static let empty = GaugeValue(utilization: 0)
}
