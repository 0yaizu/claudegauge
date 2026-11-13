import Foundation

/// Claude Code の OAuth 認証情報。必要な 2 項目だけを持つ。
/// refreshToken は意図的に持たない (更新すると Claude Code のログインを壊す恐れがあるため)。
public struct OAuthCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let expiresAt: Date

    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public var description: String { "OAuthCredential(accessToken: ***, expiresAt: \(expiresAt))" }
    public var debugDescription: String { description }
}

/// `dump()` や `Mirror` がプロパティを列挙してトークンを出さないようにする。
extension OAuthCredential: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// 入力の中身を含めないよう、ケース名だけのエラーにする。
public enum CredentialError: Error, Equatable, Sendable {
    case malformed
    case missingClaudeAiOauth
    /// `security` が失敗した (項目なし・アクセス拒否・起動失敗など)。
    case keychainUnavailable
    case timedOut
}
