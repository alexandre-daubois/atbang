import Foundation

public protocol Classifying: Sendable {
    var name: String { get }
    var model: String { get }
    func classify(_ input: String) async throws -> Triage
    func explain(_ input: String) async throws -> String
}

public enum Harness: String, CaseIterable, Sendable {
    case claudeCode = "claude"
    case appleIntelligence = "apple"

    public var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .appleIntelligence: "Apple Intelligence"
        }
    }
}

enum ModelOutput {
    static let summaryLimit = 140
    static let detailsLimit = 420

    static func sanitize(_ text: String, limit: Int) -> String {
        text.components(separatedBy: CharacterSet.controlCharacters.union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .truncated(to: limit)
    }
}
