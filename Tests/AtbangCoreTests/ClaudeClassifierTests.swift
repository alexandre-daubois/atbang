import Foundation
@testable import AtbangCore
import Testing

struct ClaudeClassifierTests {
    private func envelope(_ structuredOutput: String, isError: Bool = false) -> Data {
        Data(#"{"type":"result","is_error":\#(isError),"result":"done","structured_output":\#(structuredOutput)}"#.utf8)
    }

    @Test func parsesStructuredOutput() throws {
        let triage = try ClaudeClassifier.parse(envelope(#"{"priority":"high","summary":"Review requested from you"}"#))

        #expect(triage == Triage(priority: .high, summary: "Review requested from you"))
    }

    @Test func sanitizesTheSummary() throws {
        let triage = try ClaudeClassifier.parse(envelope(#"{"priority":"low","summary":"  Line one\nline\u0007 two‮  "}"#))

        #expect(triage.summary == "Line one line two")
    }

    @Test func capsTheSummaryLength() throws {
        let long = String(repeating: "word ", count: 60)
        let triage = try ClaudeClassifier.parse(envelope(#"{"priority":"low","summary":"\#(long)"}"#))

        #expect(triage.summary.count == ModelOutput.summaryLimit + 1)
    }

    @Test(arguments: [
        #"{"type":"result","is_error":true,"result":"Not logged in","structured_output":{"priority":"high","summary":"x"}}"#,
        #"{"type":"result","is_error":false,"result":"plain text answer"}"#,
        #"{"type":"result","is_error":false,"structured_output":{"priority":"urgent","summary":"x"}}"#,
        #"{"type":"result","is_error":false,"structured_output":{"priority":"high"}}"#,
        #"{"type":"result","is_error":false,"structured_output":{"priority":"high","summary":" \n "}}"#,
        "not json",
    ])
    func rejectsInvalidOutput(output: String) {
        #expect(throws: ClaudeClassifier.Failure.self) {
            try ClaudeClassifier.parse(Data(output.utf8))
        }
    }

    @Test func runsWithoutToolsSettingsOrMCP() {
        let arguments = ClaudeClassifier(executable: URL(filePath: "/bin/true"), model: "sonnet").arguments(system: TriagePrompt.system, schema: TriagePrompt.schema)

        #expect(arguments.first == "-p")
        #expect(arguments.contains("--model=sonnet"))
        #expect(arguments[arguments.firstIndex(of: "--tools")! + 1] == "")
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--setting-sources="))
        #expect(arguments.contains("--disable-slash-commands"))
        #expect(arguments[arguments.firstIndex(of: "--json-schema")! + 1] == TriagePrompt.schema)
        #expect(!arguments.contains { $0.contains("allowed") || $0.contains("dangerously") || $0.contains("permission") })
    }

    @Test func parsesDetails() throws {
        let details = try ClaudeClassifier.parseDetails(envelope(#"{"details":"@bob fixed the crash.\n@carol asks you to confirm on 8.3."}"#))

        #expect(details == "@bob fixed the crash. @carol asks you to confirm on 8.3.")
    }

    @Test func capsDetailsLength() throws {
        let long = String(repeating: "word ", count: 200)
        let details = try ClaudeClassifier.parseDetails(envelope(#"{"details":"\#(long)"}"#))

        #expect(details.count == ModelOutput.detailsLimit + 1)
    }

    @Test(arguments: [
        #"{"type":"result","is_error":true,"result":"Not logged in","structured_output":{"details":"x"}}"#,
        #"{"type":"result","is_error":false,"structured_output":{"priority":"high","summary":"x"}}"#,
        #"{"type":"result","is_error":false,"structured_output":{"details":" \n "}}"#,
        "not json",
    ])
    func rejectsInvalidDetails(output: String) {
        #expect(throws: ClaudeClassifier.Failure.self) {
            try ClaudeClassifier.parseDetails(Data(output.utf8))
        }
    }

    @Test func explainUsesTheDetailsPromptAndSchema() async throws {
        let directory = try temporaryDirectory()
        let script = try executable(in: directory, """
        #!/bin/sh
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        printf '%s' '{"is_error":false,"structured_output":{"details":"Longer explanation."}}'
        """)

        let details = try await ClaudeClassifier(executable: script, model: "sonnet").explain("{}")

        let arguments = try String(contentsOf: directory.appending(path: "args"), encoding: .utf8)
        #expect(details == "Longer explanation.")
        #expect(arguments.contains(TriagePrompt.detailsSchema))
        #expect(!arguments.contains(TriagePrompt.schema))
    }

    @Test func pipesTheInputThroughTheExecutable() async throws {
        let directory = try temporaryDirectory()
        let script = try executable(in: directory, """
        #!/bin/sh
        cat > "$(dirname "$0")/stdin"
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        printf '%s' '{"is_error":false,"structured_output":{"priority":"medium","summary":"Your PR has new comments"}}'
        """)

        let triage = try await ClaudeClassifier(executable: script, model: "haiku").classify(#"{"facts":{}}"#)

        #expect(triage == Triage(priority: .medium, summary: "Your PR has new comments"))
        #expect(try String(contentsOf: directory.appending(path: "stdin"), encoding: .utf8) == #"{"facts":{}}"#)
        #expect(try String(contentsOf: directory.appending(path: "args"), encoding: .utf8).contains("--model=haiku\n"))
    }

    @Test func reportsAFailingExecutable() async throws {
        let script = try executable(in: temporaryDirectory(), """
        #!/bin/sh
        echo "Invalid API key" >&2
        exit 2
        """)

        await #expect(throws: ClaudeClassifier.Failure.exit(2, "Invalid API key")) {
            try await ClaudeClassifier(executable: script, model: "sonnet").classify("{}")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "AtbangTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func executable(in directory: URL, _ source: String) throws -> URL {
        let url = directory.appending(path: "fake-claude")
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
