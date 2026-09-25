import FoundationModels

public struct AppleClassifier: Classifying {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case emptyOutput

        public var description: String { "The on-device model gave an empty answer" }
    }

    @Generable
    enum Level: String {
        case high, medium, low
    }

    @Generable
    struct Output {
        let priority: Level
        let summary: String
    }

    public let name = "Apple Intelligence"
    public let model = "apple-on-device"

    public init() {}

    public func classify(_ input: String) async throws -> Triage {
        try Self.triage(from: try await LanguageModelSession(instructions: TriagePrompt.system).respond(to: input, generating: Output.self).content)
    }

    public func explain(_ input: String) async throws -> String {
        let details = ModelOutput.sanitize(try await LanguageModelSession(instructions: TriagePrompt.detailsSystem).respond(to: input).content, limit: ModelOutput.detailsLimit)
        guard !details.isEmpty else { throw Failure.emptyOutput }
        return details
    }

    static func triage(from output: Output) throws -> Triage {
        let summary = ModelOutput.sanitize(output.summary, limit: ModelOutput.summaryLimit)
        guard !summary.isEmpty else { throw Failure.emptyOutput }
        return Triage(priority: Priority(rawValue: output.priority.rawValue)!, summary: summary)
    }
}
