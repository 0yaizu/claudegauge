import Foundation
import Testing
@testable import ClaudeGaugeCore

/// 本物の Process を使うが、echo / false / sleep だけ。Keychain には触れない。
struct ProcessCommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test("標準出力を受け取る")
    func capturesStdout() async throws {
        let result = try await runner.run("/bin/echo", arguments: ["hello"], timeout: 5)
        #expect(result.status == 0)
        #expect(String(data: result.stdout, encoding: .utf8) == "hello\n")
    }

    @Test("終了コードを返す")
    func returnsExitStatus() async throws {
        let result = try await runner.run("/usr/bin/false", arguments: [], timeout: 5)
        #expect(result.status == 1)
    }

    @Test("タイムアウトしたらプロセスを止めて timedOut")
    func timesOut() async {
        let started = Date()
        await #expect(throws: CommandError.timedOut) {
            try await runner.run("/bin/sleep", arguments: ["10"], timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("SIGTERM を無視するプロセスも SIGKILL で止める")
    func killsProcessIgnoringSigterm() async {
        let started = Date()
        await #expect(throws: CommandError.timedOut) {
            try await runner.run("/bin/sh", arguments: ["-c", "trap '' TERM; exec /bin/sleep 30"], timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("存在しない実行ファイルは launchFailed")
    func launchFailure() async {
        await #expect(throws: CommandError.launchFailed) {
            try await runner.run("/nonexistent/binary", arguments: [], timeout: 5)
        }
    }

    @Test("パイプのバッファ (64KB) を超える出力でもデッドロックしない")
    func largeOutput() async throws {
        let runner = ProcessCommandRunner(maxOutputBytes: 2 * 1024 * 1024)
        let result = try await runner.run(
            "/bin/dd", arguments: ["if=/dev/zero", "bs=1024", "count=1024"], timeout: 10
        )
        #expect(result.status == 0)
        #expect(result.stdout.count == 1024 * 1024)
    }

    @Test("出力が上限を超えたら outputTooLarge (上限を超えた分は、メモリに溜めない)")
    func outputLimit() async {
        let runner = ProcessCommandRunner(maxOutputBytes: 100_000)
        // 約 100 MB。上限が働かなければ、全部を読み込んでしまう。
        await #expect(throws: CommandError.outputTooLarge) {
            try await runner.run("/bin/dd", arguments: ["if=/dev/zero", "bs=1024", "count=100000"], timeout: 20)
        }
    }

    @Test("終わらない出力でも、上限で止めてプロセスを残さない")
    func outputLimitStopsEndlessProcess() async {
        let runner = ProcessCommandRunner(maxOutputBytes: 100_000)
        let started = Date()
        await #expect(throws: CommandError.outputTooLarge) {
            try await runner.run("/usr/bin/yes", arguments: [], timeout: 10)
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("出力が上限ちょうどなら受け取る")
    func outputExactlyAtLimit() async throws {
        let runner = ProcessCommandRunner(maxOutputBytes: 6)
        let result = try await runner.run("/bin/echo", arguments: ["hello"], timeout: 5)  // "hello\n" = 6 バイト
        #expect(result.stdout.count == 6)
    }

    @Test("子プロセスには PATH・HOME・USER だけを渡す (DYLD_* などを引き継がせない)")
    func minimalEnvironment() async throws {
        // テストを実行しているプロセスの環境には、PATH・HOME・USER 以外もある。引き継がれていれば、ここで失敗する。
        let result = try await runner.run("/usr/bin/env", arguments: [], timeout: 5)

        let keys = Set(
            String(decoding: result.stdout, as: UTF8.self)
                .split(separator: "\n")
                .compactMap { $0.split(separator: "=", maxSplits: 1).first.map(String.init) }
        )
        #expect(keys == ["PATH", "HOME", "USER"])
    }
}
