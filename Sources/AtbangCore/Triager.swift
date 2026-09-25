import Foundation

public struct TriageResult: Sendable, Equatable {
    public let threadID: String
    public var htmlURL: URL?
    public var entry: TriageCache.Entry?
    public var failure: String?
}

public struct Triager: Sendable {
    private let contexts: any ContextProviding
    private let classifier: any Classifying

    public init(contexts: any ContextProviding, classifier: any Classifying) {
        self.contexts = contexts
        self.classifier = classifier
    }

    public var fingerprint: String {
        TriagePrompt.fingerprint(model: classifier.model)
    }

    public func triage(_ notification: GitHubNotification, cached: TriageCache.Entry?) async -> TriageResult {
        var result = TriageResult(threadID: notification.id)
        if let cached, cached.isFresh(for: notification, fingerprint: fingerprint) {
            result.htmlURL = cached.htmlURL
            result.entry = cached
            return result
        }

        let context: ThreadContext
        do {
            context = try await contexts.context(for: notification)
        } catch {
            result.failure = "GitHub: \(error)"
            return result
        }

        result.htmlURL = context.htmlURL
        let input = TriagePrompt.input(for: context)
        let key = TriagePrompt.cacheKey(model: classifier.model, input: input)
        let entry = { (triage: Triage, details: String?) in
            TriageCache.Entry(key: key, fingerprint: fingerprint, updatedAt: notification.updatedAt, htmlURL: context.htmlURL, triage: triage, details: details)
        }
        if let cached, cached.key == key {
            result.entry = entry(cached.triage, cached.details)
            return result
        }

        do {
            result.entry = entry(try await classifier.classify(input), nil)
        } catch {
            result.failure = "Claude: \(error)"
        }
        return result
    }
}
