import Foundation

/// `Process` で外部コマンドを実行する。シェルは経由せず、引数は配列のまま渡す。
/// 標準エラーは読まずに捨てる (コマンドが認証情報を含む文言を出しても保持しない)。
/// 子プロセスの環境変数は PATH・HOME・USER だけにする (`DYLD_*` などを引き継がせない)。
public struct ProcessCommandRunner: CommandRunning {
    /// SIGTERM を送ってから SIGKILL に切り替えるまでの猶予。
    private static let killGracePeriod: TimeInterval = 2
    private static let readChunkSize = 65_536

    private let maxOutputBytes: Int

    /// `maxOutputBytes`: 標準出力の上限。超えたらプロセスを止めて `CommandError.outputTooLarge`。
    /// Keychain の項目は数 KB なので、既定の 1 MiB は十分に余裕がある。
    public init(maxOutputBytes: Int = 1_048_576) {
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        let limit = maxOutputBytes
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try Self.runBlocking(executable, arguments, timeout, limit) })
            }
        }
    }

    private static func runBlocking(
        _ executable: String, _ arguments: [String], _ timeout: TimeInterval, _ limit: Int
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "USER": NSUserName()]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed
        }

        let timedOut = Flag()
        let killer = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            stop(process)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        // 出力を先に読み切ってから終了を待つ (パイプが詰まって固まるのを防ぐ)。
        // 上限を超えたら、それ以上は溜めずにプロセスを止める。
        var data = Data()
        var overflowed = false
        let reader = output.fileHandleForReading
        while let chunk = try? reader.read(upToCount: readChunkSize), !chunk.isEmpty {
            data.append(chunk)
            if data.count > limit {
                overflowed = true
                data = Data()
                stop(process)
                break
            }
        }
        try? reader.close()
        process.waitUntilExit()
        killer.cancel()

        if timedOut.isSet { throw CommandError.timedOut }
        if overflowed { throw CommandError.outputTooLarge }
        return CommandResult(status: process.terminationStatus, stdout: data)
    }

    /// SIGTERM を送り、無視するプロセスは猶予のあとに SIGKILL で止める (止まらないと呼び出し側が固まる)。
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + killGracePeriod) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
