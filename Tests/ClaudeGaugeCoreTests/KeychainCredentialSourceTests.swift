import Foundation
import Testing
@testable import ClaudeGaugeCore

struct KeychainCredentialSourceTests {
    /// ダミー値のみ。
    private static let credentialsJSON = """
    {"mcpOAuth": {"x": {"accessToken": "DUMMY-MCP"}},
     "claudeAiOauth": {"accessToken": "DUMMY-ACCESS", "refreshToken": "DUMMY-REFRESH", "expiresAt": 1794394959767}}
    """

    private func success(_ text: String) -> Result<CommandResult, CommandError> {
        .success(CommandResult(status: 0, stdout: Data(text.utf8)))
    }

    @Test("security コマンドを引数配列で呼ぶ (シェルを経由しない)")
    func callsSecurityWithArguments() async throws {
        let runner = FakeCommandRunner(success(Self.credentialsJSON))
        let source = KeychainCredentialSource(runner: runner, account: "tester")

        _ = try await source.load()

        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1)
        #expect(call.executable == "/usr/bin/security")
        #expect(call.arguments == ["find-generic-password", "-a", "tester", "-s", "Claude Code-credentials", "-w"])
        #expect(call.timeout > 0)
    }

    @Test("claudeAiOauth の認証情報を返す")
    func returnsCredential() async throws {
        let source = KeychainCredentialSource(runner: FakeCommandRunner(success(Self.credentialsJSON)), account: "tester")
        let credential = try await source.load()
        #expect(credential.accessToken == "DUMMY-ACCESS")
    }

    @Test("終了コードが 0 以外なら keychainUnavailable。stdout の中身はエラーに含めない")
    func nonZeroStatus() async {
        let runner = FakeCommandRunner(.success(CommandResult(status: 44, stdout: Data("DUMMY-LEAK".utf8))))
        let source = KeychainCredentialSource(runner: runner, account: "tester")

        await #expect(throws: CredentialError.keychainUnavailable) { try await source.load() }
        do {
            _ = try await source.load()
            Issue.record("エラーになるはず")
        } catch {
            #expect(!"\(error)".contains("DUMMY-LEAK"))
        }
    }

    @Test("起動に失敗したら keychainUnavailable")
    func launchFailed() async {
        let source = KeychainCredentialSource(runner: FakeCommandRunner(.failure(.launchFailed)), account: "tester")
        await #expect(throws: CredentialError.keychainUnavailable) { try await source.load() }
    }

    @Test("応答待ちで止まったらタイムアウト")
    func timedOut() async {
        let source = KeychainCredentialSource(runner: FakeCommandRunner(.failure(.timedOut)), account: "tester")
        await #expect(throws: CredentialError.timedOut) { try await source.load() }
    }

    @Test("中身が壊れていれば malformed、claudeAiOauth が無ければ missingClaudeAiOauth")
    func parseErrorsPropagate() async {
        let broken = KeychainCredentialSource(runner: FakeCommandRunner(success("not json")), account: "tester")
        await #expect(throws: CredentialError.malformed) { try await broken.load() }

        let missing = KeychainCredentialSource(runner: FakeCommandRunner(success(#"{"mcpOAuth": {}}"#)), account: "tester")
        await #expect(throws: CredentialError.missingClaudeAiOauth) { try await missing.load() }
    }
}
