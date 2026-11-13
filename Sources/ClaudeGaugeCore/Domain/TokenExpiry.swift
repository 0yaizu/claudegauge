import Foundation

public enum TokenExpiry {
    /// 期限までこれ未満なら、リクエスト中に切れる恐れがあるため期限切れ扱いにする。
    public static let margin: TimeInterval = 300

    public static func isExpired(expiresAt: Date, now: Date) -> Bool {
        expiresAt < now.addingTimeInterval(margin)
    }
}
