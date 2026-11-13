import Foundation

/// ポップオーバーの 1 枠 (5h session / Weekly) の表示内容。
/// 文字列と割合を先に組み立てておき、UI は並べるだけにする (UI なしでテストできる)。
///
///     5h session                 60%  Forecast: 120% (100% at 21:40)
///     [██████████░░░░░░░░░░]
///     Resets at 21:40 (3h30m remain)
public struct WindowRowModel: Equatable, Sendable {
    public let title: String
    public let percentText: String
    public let forecastText: String
    /// リセット前に 100% へ届く場合だけ。
    public let reachText: String?
    /// リセット時刻が分からない枠では nil。
    public let resetsText: String?
    /// 棒グラフの塗り割合 (0...1)。
    public let fraction: Double
    public let level: UsageLevel

    public static func make(
        title: String,
        usage: WindowUsage?,
        windowLength: TimeInterval,
        now: Date,
        timeZone: TimeZone = .current
    ) -> WindowRowModel {
        guard let usage else { return placeholder(title: title) }

        let forecast = WindowForecast.make(
            utilization: usage.utilization, resetsAt: usage.resetsAt, windowLength: windowLength, now: now
        )
        let gauge = GaugeValue(utilization: usage.utilization)
        return WindowRowModel(
            title: title,
            percentText: DisplayFormatter.percent(usage.utilization),
            forecastText: DisplayFormatter.forecastLabel(forecast),
            // 目安の間は、外れやすい時刻で警告しないよう、(100% at …) を出さない。
            reachText: forecast.flatMap {
                $0.isRough ? nil : DisplayFormatter.reachLabel($0.timeToFull, now: now, timeZone: timeZone)
            },
            resetsText: usage.resetsAt.map { DisplayFormatter.resetsLine($0, now: now, timeZone: timeZone) },
            fraction: gauge.fraction,
            level: gauge.level
        )
    }

    /// 枠が返ってこない場合 (Pro プランの 5h など)。
    public static func placeholder(title: String) -> WindowRowModel {
        WindowRowModel(
            title: title,
            percentText: DisplayFormatter.percent(.nan),
            forecastText: DisplayFormatter.forecastLabel(nil),
            reachText: nil,
            resetsText: nil,
            fraction: 0,
            level: .normal
        )
    }
}
