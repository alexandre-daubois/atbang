import Foundation

public protocol Classifying: Sendable {
    var model: String { get }
    func classify(_ input: String) async throws -> Triage
}

public struct ClaudeClassifier: Classifying {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case timedOut
        case exit(Int32, String)
        case invalidOutput(String)

        public var description: String {
            switch self {
            case .timedOut: "claude timed out"
            case let .exit(status, message): "claude exited with \(status): \(message)"
            case let .invalidOutput(message): "Unexpected claude output: \(message)"
            }
        }
    }

    static let summaryLimit = 140
    static let detailsLimit = 420

    public let executable: URL
    public let model: String

    public init(executable: URL, model: String) {
        self.executable = executable
        self.model = model
    }

    /// No tools, no MCP servers, no settings, CLAUDE.md or skills: the thread text reaches a model that can
    /// only answer through the schema.
    func arguments(system: String, schema: String) -> [String] {
        [
            "-p",
            "--model=\(model)",
            "--output-format", "json",
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources=",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--system-prompt", system,
            "--json-schema", schema,
        ]
    }

    public func classify(_ input: String) async throws -> Triage {
        try Self.parse(await run(input, system: TriagePrompt.system, schema: TriagePrompt.schema))
    }

    public func explain(_ input: String) async throws -> String {
        try Self.parseDetails(await run(input, system: TriagePrompt.detailsSystem, schema: TriagePrompt.detailsSchema))
    }

    private func run(_ input: String, system: String, schema: String) async throws -> Data {
        let output = try await ProcessRunner.run(
            executable,
            arguments: arguments(system: system, schema: schema),
            input: Data(input.utf8),
            currentDirectory: FileManager.default.temporaryDirectory
        )
        if output.timedOut { throw Failure.timedOut }
        guard output.status == 0 else {
            let detail = output.stderrText.isEmpty ? String(decoding: output.stdout.prefix(300), as: UTF8.self) : output.stderrText
            throw Failure.exit(output.status, String(detail.prefix(300)))
        }
        return output.stdout
    }

    static func parse(_ data: Data) throws -> Triage {
        let triage = try structuredOutput(data, as: Triage.self)
        let summary = sanitize(triage.summary, limit: summaryLimit)
        guard !summary.isEmpty else { throw Failure.invalidOutput("empty summary") }
        return Triage(priority: triage.priority, summary: summary)
    }

    static func parseDetails(_ data: Data) throws -> String {
        struct Details: Decodable { let details: String }
        let details = sanitize(try structuredOutput(data, as: Details.self).details, limit: detailsLimit)
        guard !details.isEmpty else { throw Failure.invalidOutput("empty details") }
        return details
    }

    private static func structuredOutput<T: Decodable>(_ data: Data, as _: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope: Envelope<T>
        do {
            envelope = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            throw Failure.invalidOutput(String(describing: error))
        }
        guard envelope.isError != true, let output = envelope.structuredOutput else {
            throw Failure.invalidOutput(String((envelope.result ?? "no structured output").prefix(300)))
        }
        return output
    }

    static func sanitize(_ text: String, limit: Int) -> String {
        text.components(separatedBy: CharacterSet.controlCharacters.union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .truncated(to: limit)
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let isError: Bool?
    let result: String?
    let structuredOutput: T?
}
