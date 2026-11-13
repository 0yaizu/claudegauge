import Foundation

/// 「いつ API を叩いてよいか」のルール。時刻は引数で受け取り、I/O を持たない。
public enum RefreshPolicy {
    public static let minimumInterval: TimeInterval = 60
    public static let maximumInterval: TimeInterval = 600
    public static let defaultInterval: TimeInterval = 180

    /// Reload ボタンの連打対策。前回の試行からこれ未満なら拒否する。
    public static let reloadCooldown: TimeInterval = 60

    /// 429 を受け続けても、間隔はこれ以上に延ばさない。
    public static let maximumBackoffInterval: TimeInterval = 1800

    /// バックオフの段数 (429・Keychain の失敗の連続回数) の上限。最短の間隔 (60 秒) でも、2^5 倍で上の上限に届くので、これで十分。
    /// 保存データが書き換えられても、加算でオーバーフローしないようにするための歯止めでもある。
    public static let maximumBackoffSteps = 10

    /// 設定値を 1〜10 分に丸める。
    public static func clampedInterval(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, minimumInterval), maximumInterval)
    }

    /// `lastAttemptAt` は成功・失敗を問わない直近の取得試行時刻。
    /// 未来の時刻 (時計が戻った場合) は無視して許可する。
    public static func canReload(lastAttemptAt: Date?, now: Date) -> Bool {
        guard let lastAttemptAt else { return true }
        let elapsed = now.timeIntervalSince(lastAttemptAt)
        return elapsed < 0 || elapsed >= reloadCooldown
    }

    /// 次の自動更新までの待ち時間。前回の試行から `interval` が経つまで。
    /// 設定で間隔を変えたり、Reload で試行時刻が進んだりしたときに、残りの待ち時間を計算し直すために使う。
    public static func delayUntilNextRefresh(lastAttemptAt: Date?, interval: TimeInterval, now: Date) -> TimeInterval {
        guard let lastAttemptAt else { return 0 }
        let remaining = lastAttemptAt.addingTimeInterval(interval).timeIntervalSince(now)
        // 時計が戻って前回の試行が未来になっても、間隔より長くは待たない。
        return min(max(remaining, 0), interval)
    }

    /// 失敗 (429・Keychain を読めない) の連続回数に応じて間隔を倍々にする。
    public static func backoffInterval(base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        // 指数が大きすぎて inf になっても、上限で丸まる。
        min(base * pow(2, Double(max(consecutiveFailures, 0))), maximumBackoffInterval)
    }
}
