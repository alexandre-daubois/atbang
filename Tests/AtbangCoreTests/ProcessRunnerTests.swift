import Foundation
@testable import AtbangCore
import Testing

struct ProcessRunnerTests {
    @Test func feedsStdinAndCollectsStdout() async throws {
        let output = try await ProcessRunner.run(URL(filePath: "/bin/cat"), arguments: [], input: Data("hello".utf8))

        #expect(output.status == 0)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hello")
        #expect(!output.timedOut)
    }

    @Test func drainsOutputLargerThanThePipeBuffer() async throws {
        let output = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "head -c 300000 /dev/zero"])

        #expect(output.stdout.count == 300_000)
    }

    @Test func reportsExitStatusAndStderr() async throws {
        let output = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo oops >&2; exit 3"])

        #expect(output.status == 3)
        #expect(output.stderrText == "oops")
    }

    @Test func survivesAChildThatIgnoresStdin() async throws {
        let output = try await ProcessRunner.run(URL(filePath: "/usr/bin/true"), arguments: [], input: Data(count: 1_000_000))

        #expect(output.status == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func manyConcurrentShortRunsAllComplete() async {
        let finished = await withTaskGroup(of: Bool.self) { group in
            var finished = 0
            for index in 0..<300 {
                if index >= 6, await group.next() == true { finished += 1 }
                group.addTask { (try? await ProcessRunner.run(URL(filePath: "/bin/echo"), arguments: ["\(index)"]))?.status == 0 }
            }
            for await succeeded in group where succeeded { finished += 1 }
            return finished
        }

        #expect(finished == 300)
    }

    @Test func killsAChildPastTheTimeout() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let output = try await ProcessRunner.run(URL(filePath: "/bin/sleep"), arguments: ["10"], timeout: .milliseconds(200))

        #expect(output.timedOut)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func throwsWhenTheExecutableIsMissing() async {
        await #expect(throws: (any Error).self) {
            try await ProcessRunner.run(URL(filePath: "/nonexistent/claude"), arguments: [])
        }
    }

    @Test func locatesExecutablesUnderTheHomeLocalBin() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "AtbangHome-\(UUID().uuidString)")
        let bin = home.appending(path: ".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = "tool-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: bin.appending(path: tool).path, contents: Data(), attributes: [.posixPermissions: 0o755])
        FileManager.default.createFile(atPath: bin.appending(path: "\(tool)-plain").path, contents: Data(), attributes: [.posixPermissions: 0o644])

        #expect(Executable.locate(tool, home: home) == bin.appending(path: tool).path)
        #expect(Executable.locate("\(tool)-plain", home: home) == nil)
    }
}
