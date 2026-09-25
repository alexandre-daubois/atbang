import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool

    public var stderrText: String {
        String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ProcessRunner {
    public static func run(
        _ executable: URL,
        arguments: [String],
        input: Data = Data(),
        currentDirectory: URL? = nil,
        timeout: Duration = .seconds(180)
    ) async throws -> ProcessOutput {
        // Writing to a child that already exited raises SIGPIPE, which would kill the app.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // `waitUntilExit()` from a dispatch thread can miss the exit and block forever, the handler cannot.
        let (exited, exit) = AsyncStream.makeStream(of: Void.self)
        process.terminationHandler = { _ in exit.finish() }
        try process.run()

        let deadline = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
            return true
        }

        return await withTaskCancellationHandler {
            async let out = blocking { stdout.fileHandleForReading.readDataToEndOfFile() }
            async let err = blocking { stderr.fileHandleForReading.readDataToEndOfFile() }
            await blocking {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
            let (outData, errData) = await (out, err)
            for await _ in exited {}
            deadline.cancel()
            let timedOut = (try? await deadline.value) ?? false
            return ProcessOutput(status: process.terminationStatus, stdout: outData, stderr: errData, timedOut: timedOut)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: work()) }
        }
    }
}

public enum Executable {
    public static func locate(_ name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        ["\(home.path)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
