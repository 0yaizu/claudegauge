import Foundation

/// メニューバーの絵の形式。
public enum MenuBarStyle: String, CaseIterable, Sendable {
    /// 入れ子ドーナツ (外側が 5h、内側が weekly)。
    case donut
    /// 横棒 2 本 (上が 5h、下が weekly)。
    case bar
}

/// ユーザーが変えられる設定。UserDefaults への読み書きと、壊れた値の補正をここで持つ。
/// ログイン時の自動起動は OS 側の登録状態が正なので、ここでは持たない。
public struct AppSettings: Equatable, Sendable {
    enum Keys {
        static let style = "menuBarStyle"
        static let refreshInterval = "refreshInterval"
        static let showsPercentText = "showsPercentText"
    }

    /// 設定画面で選べる更新間隔 (秒)。1 / 3 / 5 / 10 分。
    public static let intervalChoices: [TimeInterval] = [60, 180, 300, 600]

    public var style: MenuBarStyle
    public var refreshInterval: TimeInterval
    /// メニューバーに % の数値を並べるか。切ると絵だけになり、幅が小さくなる。
    public var showsPercentText: Bool

    public init(
        style: MenuBarStyle = .donut,
        refreshInterval: TimeInterval = RefreshPolicy.defaultInterval,
        showsPercentText: Bool = true
    ) {
        self.style = style
        self.refreshInterval = RefreshPolicy.clampedInterval(refreshInterval)
        self.showsPercentText = showsPercentText
    }

    /// 保存されていない・壊れている項目は初期値にする。
    public init(defaults: UserDefaults) {
        self.init(
            style: defaults.string(forKey: Keys.style).flatMap(MenuBarStyle.init(rawValue:)) ?? .donut,
            refreshInterval: defaults.object(forKey: Keys.refreshInterval) as? Double ?? RefreshPolicy.defaultInterval,
            showsPercentText: defaults.object(forKey: Keys.showsPercentText) as? Bool ?? true
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: Keys.style)
        defaults.set(refreshInterval, forKey: Keys.refreshInterval)
        defaults.set(showsPercentText, forKey: Keys.showsPercentText)
    }
}
