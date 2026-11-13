import Foundation

/// 画面に出す文字列を作る。SwiftUI から切り離してあり、UI なしでテストできる。
public enum DisplayFormatter {
    private static let unavailable = "—"
    /// これ以上の絶対値は API の異常値とみなし、整数変換 (範囲外でクラッシュする) に進めない。
    private static let maximumPercent = 1e9
    private static let maximumSeconds = 1e10

    public static let tokenExpiredNotice = "Open Claude Code once to refresh"

    /// 使用率を四捨五入した整数 % にする。例: 42.5 → "43%"
    public static func percent(_ value: Double) -> String {
        guard value.isFinite, abs(value) < maximumPercent else { return unavailable }
        return "\(Int(value.rounded()))%"
    }

    /// 残り時間。英語の短縮表記で 2 単位まで。例: "3h30m" / "6d3h" / "<1m"
    public static func remaining(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, abs(seconds) < maximumSeconds else { return unavailable }
        let totalMinutes = Int(max(seconds, 0) / 60)
        guard totalMinutes >= 1 else { return "<1m" }

        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? "\(days)d\(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// リセット時点の予測使用率。どの % でも表示し、100% を超えてもそのまま出す。
    /// 計測中は "Forecast: measuring"、予測できない枠 (nil) は "Forecast: —"。
    /// 経過率が低く外れやすい予測 (目安) には "~" を付ける。例: "Forecast: ~141%"
    public static func forecastLabel(_ forecast: WindowForecast?) -> String {
        guard let forecast else { return "Forecast: \(unavailable)" }
        guard let projected = forecast.projectedFinalPercent else { return "Forecast: measuring" }
        return "Forecast: \(forecast.isRough ? "~" : "")\(percent(projected))"
    }

    /// Forecast の隣に添える "(100% at 21:40)"。リセット前に 100% へ届く場合だけ返し、それ以外は nil。
    public static func reachLabel(
        _ timeToFull: WindowForecast.TimeToFull,
        now: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        guard case let .at(date) = timeToFull else { return nil }
        return "(100% at \(clock(date, now: now, timeZone: timeZone)))"
    }

    /// "Resets at 21:40 (3h30m remain)"。別の日なら "Resets at 11/18 10:00 (7d remain)"。
    /// API は境界を `10:59:59.9` のように返すため、最寄りの分 (11:00) に丸めてから表示する。
    public static func resetsLine(_ resetsAt: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let rounded = roundedToMinute(resetsAt)
        let time = clock(rounded, now: now, timeZone: timeZone)
        let remain = remaining(rounded.timeIntervalSince(now))
        return "Resets at \(time) (\(remain) remain)"
    }

    private static func roundedToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded() * 60)
    }

    /// 最終更新。失敗時も特別な表記はせず、最後に成功した時刻をそのまま出す。
    public static func lastUpdated(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        "Last updated \(clock(date, now: now, timeZone: timeZone))"
    }

    /// 時刻は "19:35" 形式。別の日なら日付を添えて "11/12 06:59"。
    public static func clock(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        return "\(parts.month ?? 0)/\(parts.day ?? 0) \(time)"
    }
}
