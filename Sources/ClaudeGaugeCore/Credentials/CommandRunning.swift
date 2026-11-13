import Foundation

/// `stdout` には、`security -w` が返す Keychain 項目全体 (他のツールのトークンを含む) が入りうる。
/// 誤って表示してもログに残らないよう、文字列化と `dump` / `Mirror` では中身を出さない。
public struct CommandResult: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let status: Int32
    public let stdout: Data

    public init(status: Int32, stdout: Data) {
        self.status = status
        self.stdout = stdout
    }

    public var description: String { "CommandResult(status: \(status), stdout: <\(stdout.count) bytes redacted>)" }
    public var debugDescription: String { description }
}

extension CommandResult: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// 出力の中身を含めないよう、ケース名だけのエラーにする。
public enum CommandError: Error, Equatable, Sendable {
    case timedOut
    case launchFailed
    /// 出力が上限を超えた。異常な出力でメモリを使い切らないよう、プロセスを止めて打ち切る。
    case outputTooLarge
}

/// 外部コマンドの実行。テストでは偽物に差し替える。
public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}
