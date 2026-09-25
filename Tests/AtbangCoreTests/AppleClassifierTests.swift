import Foundation
import FoundationModels
@testable import AtbangCore
import Testing

struct AppleClassifierTests {
    @Test func convertsTheGeneratedOutput() throws {
        let triage = try AppleClassifier.triage(from: .init(priority: .medium, summary: "  Your PR:\nchanges requested by @dave\u{0007}  "))

        #expect(triage == Triage(priority: .medium, summary: "Your PR: changes requested by @dave"))
    }

    @Test func capsTheSummaryLength() throws {
        let triage = try AppleClassifier.triage(from: .init(priority: .low, summary: String(repeating: "word ", count: 60)))

        #expect(triage.summary.count == ModelOutput.summaryLimit + 1)
    }

    @Test func rejectsAnEmptySummary() {
        #expect(throws: AppleClassifier.Failure.emptyOutput) {
            try AppleClassifier.triage(from: .init(priority: .high, summary: " \n "))
        }
    }

    @Test(.enabled(if: SystemLanguageModel.default.isAvailable)) func triagesWithTheOnDeviceModel() async throws {
        let context = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.pullRequest), notification: Fixtures.notification(), viewer: "alice")
        let input = TriagePrompt.input(for: context)

        let triage = try await AppleClassifier().classify(input)
        let details = try await AppleClassifier().explain(input)

        #expect(!triage.summary.isEmpty)
        #expect(!details.isEmpty)
    }
}
