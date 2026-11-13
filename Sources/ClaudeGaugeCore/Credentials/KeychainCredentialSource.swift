import Foundation

/// Claude Code が保存した認証情報を Keychain から読む。毎回読み直し、保持や保存はしない。
public struct KeychainCredentialSource: CredentialSource {
    static let executable = "/usr/bin/security"
    static let service = "Claude Code-credentials"
    /// Keychain がロックされ、応答待ちで止まる場合への備え。
    static let timeout: TimeInterval = 15

    private let runner: any CommandRunning
    private let account: String

    public init(runner: any CommandRunning = ProcessCommandRunner(), account: String = NSUserName()) {
        self.runner = runner
        self.account = account
    }

    public func load() async throws -> OAuthCredential {
        let result: CommandResult
        do {
            result = try await runner.run(
                Self.executable,
                arguments: ["find-generic-password", "-a", account, "-s", Self.service, "-w"],
                timeout: Self.timeout
            )
        } catch CommandError.timedOut {
            throw CredentialError.timedOut
        } catch {
            throw CredentialError.keychainUnavailable
        }
        // 終了コード以外 (stdout など) はエラーに含めない。
        guard result.status == 0 else { throw CredentialError.keychainUnavailable }
        return try CredentialParser.parse(result.stdout)
    }
}
