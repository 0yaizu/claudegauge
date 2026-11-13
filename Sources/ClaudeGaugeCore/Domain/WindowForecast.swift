import Foundation

/// 現在のペースが続いた場合の予測 (線形外挿)。
public struct WindowForecast: Equatable, Sendable {
    public enum TimeToFull: Equatable, Sendable {
        /// 経過率が低く、予測の精度が出ない。
        case measuring
        /// すでに 100% 以上。
        case reached
        /// リセットまでに 100% へ届かない。
        case notReached
        /// 今のペースだと、リセットより前のこの時点で 100% に届く。
        case at(Date)
    }

    /// これ未満の経過率では予測しない (計測中)。
    public static let minimumElapsedRatio = 0.03
    /// これ未満の経過率の予測は「目安」(外れやすい) として扱う。`~` を付け、警告にはしない。
    public static let reliableElapsedRatio = 0.1

    public static let fiveHourLength: TimeInterval = 5 * 3600
    public static let weeklyLength: TimeInterval = 7 * 24 * 3600

    /// 0...1
    public let elapsedRatio: Double
    /// リセット時点の予測使用率。計測中は nil。
    public let projectedFinalPercent: Double?
    public let timeToFull: TimeToFull

    /// 経過率が低く、外れやすい予測か。すでに 100% 以上 (事実) や計測中 (予測なし) は含まない。
    public var isRough: Bool {
        guard elapsedRatio < Self.reliableElapsedRatio else { return false }
        switch timeToFull {
        case .at, .notReached: return true
        case .measuring, .reached: return false
        }
    }

    /// リセット前に 100% へ届く (または届いている) か。目安の間は、外れやすいので警告にしない。
    public var isWarning: Bool {
        switch timeToFull {
        case .reached: true
        case .at: !isRough
        case .measuring, .notReached: false
        }
    }

    /// `resetsAt` が無い (ウィンドウ未開始) 場合は nil。
    /// `resetsAt` が過去 (古い値) の場合は、経過率 1 として扱う。
    public static func make(
        utilization: Double,
        resetsAt: Date?,
        windowLength: TimeInterval,
        now: Date
    ) -> WindowForecast? {
        guard let resetsAt, windowLength > 0 else { return nil }

        let windowStart = resetsAt.addingTimeInterval(-windowLength)
        let elapsed = min(max(now.timeIntervalSince(windowStart), 0), windowLength)
        let ratio = elapsed / windowLength

        if utilization >= 100 {
            return WindowForecast(elapsedRatio: ratio, projectedFinalPercent: utilization, timeToFull: .reached)
        }
        if ratio < minimumElapsedRatio {
            return WindowForecast(elapsedRatio: ratio, projectedFinalPercent: nil, timeToFull: .measuring)
        }

        let projected = utilization * windowLength / elapsed
        let timeToFull: TimeToFull = projected > 100
            ? .at(now.addingTimeInterval((100 - utilization) * elapsed / utilization))
            : .notReached
        return WindowForecast(elapsedRatio: ratio, projectedFinalPercent: projected, timeToFull: timeToFull)
    }
}
