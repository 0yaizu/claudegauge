/// 使用率に応じた警告レベル。緑 / 黄 / 赤に対応する。
public enum UsageLevel: Equatable, Sendable {
    case normal
    case caution
    case critical

    public static let cautionThreshold = 70.0
    public static let criticalThreshold = 90.0

    public init(percent: Double) {
        switch percent {
        case ..<Self.cautionThreshold: self = .normal
        case ..<Self.criticalThreshold: self = .caution
        default: self = .critical
        }
    }
}
