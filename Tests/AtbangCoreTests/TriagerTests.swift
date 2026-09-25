import Foundation
@testable import AtbangCore
import Testing

private actor CallCounter {
    private(set) var inputs: [String] = []
    func record(_ input: String) { inputs.append(input) }
}

private struct StubContexts: ContextProviding {
    let result: Result<ThreadContext, GitHubClient.Failure>
    let calls = CallCounter()

    func context(for notification: GitHubNotification) async throws -> ThreadContext {
        await calls.record(notification.id)
        return try result.get()
    }
}

private struct StubClassifier: Classifying {
    var model = "sonnet"
    let result: Result<Triage, ClaudeClassifier.Failure>
    let calls = CallCounter()

    func classify(_ input: String) async throws -> Triage {
        await calls.record(input)
        return try result.get()
    }
}

struct TriagerTests {
    private let notification = Fixtures.notification()
    private let context = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.pullRequest), notification: Fixtures.notification(), viewer: "alice")
    private let triage = Triage(priority: .high, summary: "Review requested from you")
    private let cachedTriage = Triage(priority: .low, summary: "Cached")

    private var key: String {
        TriagePrompt.cacheKey(model: "sonnet", input: TriagePrompt.input(for: context))
    }

    private func entry(key: String, fingerprint: String = TriagePrompt.fingerprint(model: "sonnet"), updatedAt: Date? = nil, triage: Triage, details: String? = nil) -> TriageCache.Entry {
        TriageCache.Entry(key: key, fingerprint: fingerprint, updatedAt: updatedAt ?? notification.updatedAt, htmlURL: context.htmlURL, triage: triage, details: details)
    }

    @Test func classifiesAnUncachedThread() async {
        let classifier = StubClassifier(result: .success(triage))
        let result = await Triager(contexts: StubContexts(result: .success(context)), classifier: classifier).triage(notification, cached: nil)

        #expect(result == TriageResult(threadID: "1", htmlURL: context.htmlURL, entry: entry(key: key, triage: triage)))
        #expect(await classifier.calls.inputs == [TriagePrompt.input(for: context)])
    }

    @Test func skipsGitHubAndClaudeWhenTheThreadHasNoNewActivity() async {
        let cached = entry(key: "anything", triage: cachedTriage)
        let contexts = StubContexts(result: .success(context))
        let classifier = StubClassifier(result: .success(triage))
        let result = await Triager(contexts: contexts, classifier: classifier).triage(notification, cached: cached)

        #expect(result == TriageResult(threadID: "1", htmlURL: context.htmlURL, entry: cached))
        #expect(await contexts.calls.inputs.isEmpty)
        #expect(await classifier.calls.inputs.isEmpty)
    }

    @Test func newActivityWithTheSameContentKeepsTheTriageWithoutClaude() async {
        let cached = entry(key: key, updatedAt: notification.updatedAt.addingTimeInterval(-60), triage: cachedTriage, details: "Longer")
        let contexts = StubContexts(result: .success(context))
        let classifier = StubClassifier(result: .success(triage))
        let result = await Triager(contexts: contexts, classifier: classifier).triage(notification, cached: cached)

        #expect(result.entry == entry(key: key, triage: cachedTriage, details: "Longer"))
        #expect(await contexts.calls.inputs == ["1"])
        #expect(await classifier.calls.inputs.isEmpty)
    }

    @Test func reclassifiesWhenTheThreadChanged() async {
        let cached = entry(key: "stale", updatedAt: notification.updatedAt.addingTimeInterval(-60), triage: cachedTriage, details: "Outdated")
        let classifier = StubClassifier(result: .success(triage))
        let result = await Triager(contexts: StubContexts(result: .success(context)), classifier: classifier).triage(notification, cached: cached)

        #expect(result.entry == entry(key: key, triage: triage))
        #expect(result.entry?.details == nil)
        #expect(await classifier.calls.inputs.count == 1)
    }

    @Test func reclassifiesWhenTheModelChanged() async {
        let cached = entry(key: key, triage: cachedTriage)
        let classifier = StubClassifier(model: "opus", result: .success(triage))
        let result = await Triager(contexts: StubContexts(result: .success(context)), classifier: classifier).triage(notification, cached: cached)

        #expect(result.entry?.triage == triage)
        #expect(result.entry?.fingerprint == TriagePrompt.fingerprint(model: "opus"))
        #expect(await classifier.calls.inputs.count == 1)
    }

    @Test func reportsGitHubFailuresWithoutCallingClaude() async {
        let classifier = StubClassifier(result: .success(triage))
        let contexts = StubContexts(result: .failure(.http(502, "Bad gateway")))
        let result = await Triager(contexts: contexts, classifier: classifier).triage(notification, cached: nil)

        #expect(result == TriageResult(threadID: "1", failure: "GitHub: GitHub answered 502: Bad gateway"))
        #expect(await classifier.calls.inputs.isEmpty)
    }

    @Test func reportsClaudeFailuresAndKeepsTheLink() async {
        let classifier = StubClassifier(result: .failure(.timedOut))
        let result = await Triager(contexts: StubContexts(result: .success(context)), classifier: classifier).triage(notification, cached: nil)

        #expect(result == TriageResult(threadID: "1", htmlURL: context.htmlURL, failure: "Claude: claude timed out"))
    }
}
