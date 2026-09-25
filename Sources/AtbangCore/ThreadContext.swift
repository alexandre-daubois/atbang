import Foundation

/// Signals computed by the app from GitHub's API: Claude may rely on them.
public struct Facts: Codable, Sendable, Equatable {
    public struct LastActivity: Codable, Sendable, Equatable {
        public let author: String
        public let kind: String
        public let at: Date
    }

    public var kind: String
    public var repository: String
    public var number: Int?
    public var notificationReason: String
    public var viewer: String
    public var state: String?
    public var isDraft: Bool?
    public var author: String?
    public var viewerIsAuthor: Bool?
    public var viewerIsAssignee: Bool?
    public var reviewRequestedFromViewer: Bool?
    public var reviewRequestedFromTeams: [String]?
    public var reviewDecision: String?
    public var latestReviewByReviewer: [String: String]?
    public var newCommitsSinceViewerReview: Bool?
    public var ciStatus: String?
    public var hasMergeConflict: Bool?
    public var severity: String?
    public var viewerIsAdvisoryCollaborator: Bool?
    public var lastActivity: LastActivity?
    public var viewerWroteLastActivity: Bool?
    public var viewerLastActivityAt: Date?
    public var activityCountSinceLastRead: Int?
    public var viewerMentionedSinceViewerLastActivity: Bool?

    init(_ notification: GitHubNotification, kind: String, viewer: String) {
        self.kind = kind
        repository = notification.repository.fullName
        number = notification.number
        notificationReason = notification.reason
        self.viewer = viewer
    }
}

/// Text written by third parties: only ever summarized, never obeyed.
public struct UntrustedContent: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let author: String
        public let kind: String
        public let at: Date
        public var path: String?
        public let body: String
    }

    public let title: String
    public var body: String?
    public var recentActivity: [Entry]?
}

public struct ThreadContext: Sendable, Equatable {
    public let htmlURL: URL
    public let facts: Facts
    public let untrusted: UntrustedContent

    static let bodyLimit = 4000
    static let entryLimit = 1500
    static let recentActivityLimit = 20
}

public protocol ContextProviding: Sendable {
    func context(for notification: GitHubNotification) async throws -> ThreadContext
}

public actor GitHubContextProvider: ContextProviding {
    private let client: GitHubClient
    private let viewer: String
    private var advisoriesByRepository: [String: Task<[Advisory], Error>] = [:]

    public init(client: GitHubClient, viewer: String) {
        self.client = client
        self.viewer = viewer
    }

    public func context(for notification: GitHubNotification) async throws -> ThreadContext {
        let parts = notification.repository.fullName.split(separator: "/").map(String.init)
        let variables = ThreadVariables(owner: parts.first ?? "", name: parts.last ?? "", number: notification.number ?? 0)
        switch (notification.subject.type, notification.number) {
        case ("PullRequest", .some):
            let data = try await client.query(ThreadQueries.pullRequest, variables: variables, as: PullRequestData.self)
            guard let pullRequest = data.repository?.pullRequest else { throw GitHubClient.Failure.graphQL("pull request not found") }
            return ThreadContext.pullRequest(pullRequest, notification: notification, viewer: viewer)
        case ("Issue", .some):
            let data = try await client.query(ThreadQueries.issue, variables: variables, as: IssueData.self)
            guard let issue = data.repository?.issue else { throw GitHubClient.Failure.graphQL("issue not found") }
            return ThreadContext.issue(issue, notification: notification, viewer: viewer)
        case ("RepositoryAdvisory", _):
            let advisory = try await advisories(in: notification.repository.fullName).first { $0.summary == notification.subject.title }
            return ThreadContext.advisory(advisory, notification: notification, viewer: viewer)
        default:
            guard let url = notification.subject.url else { return ThreadContext.generic(notification, htmlURL: nil, viewer: viewer) }
            return ThreadContext.generic(notification, htmlURL: try await client.htmlURL(of: url), viewer: viewer)
        }
    }

    private func advisories(in repository: String) async throws -> [Advisory] {
        if let pending = advisoriesByRepository[repository] { return try await pending.value }
        let task = Task { [client] in try await client.advisories(in: repository) }
        advisoriesByRepository[repository] = task
        return try await task.value
    }
}

extension ThreadContext {
    static func pullRequest(_ pr: PullRequestNode, notification: GitHubNotification, viewer: String) -> ThreadContext {
        let lastCommit = pr.commits.items.last?.commit
        var events = [Event(author: pr.author.displayLogin, kind: "opened", at: pr.createdAt, body: pr.body)]
        // Commit authors and dates are whatever the committer typed, so a commit only counts on the viewer's own pull
        // request, where others rarely push, and never later than the activity GitHub itself recorded.
        if let lastCommit, let login = lastCommit.author?.user?.login, pr.author.displayLogin == viewer {
            events.append(Event(author: login, kind: "commit", at: min(lastCommit.committedDate, notification.updatedAt), body: ""))
        }
        events += pr.comments.items.map { Event(author: $0.author.displayLogin, kind: "comment", at: $0.createdAt, body: $0.body) }
        for review in pr.reviews.items where review.state != "PENDING" {
            guard let submittedAt = review.submittedAt else { continue }
            if review.state != "COMMENTED" || !review.body.isEmpty {
                events.append(Event(author: review.author.displayLogin, kind: "review_\(review.state.lowercased())", at: submittedAt, body: review.body))
            }
            events += review.comments.items.map {
                Event(author: $0.author.displayLogin, kind: "review_comment", at: $0.createdAt, body: $0.body, path: $0.path)
            }
        }

        let reviewers = pr.reviewRequests.items.compactMap(\.requestedReviewer)
        let latestReviews = pr.latestReviews.items.filter { $0.state != "PENDING" }
        let viewerReview = latestReviews.first { $0.author.displayLogin == viewer }

        var facts = Facts(notification, kind: "pull_request", viewer: viewer)
        facts.state = pr.merged ? "merged" : pr.state.lowercased()
        facts.isDraft = pr.isDraft
        facts.author = pr.author.displayLogin
        facts.viewerIsAuthor = pr.author.displayLogin == viewer
        facts.viewerIsAssignee = pr.assignees.items.contains { $0.displayLogin == viewer }
        facts.reviewRequestedFromViewer = reviewers.contains { $0.typename == "User" && $0.login == viewer }
        facts.reviewRequestedFromTeams = reviewers.compactMap(\.combinedSlug)
        facts.reviewDecision = pr.reviewDecision
        facts.latestReviewByReviewer = Dictionary(latestReviews.map { ($0.author.displayLogin, $0.state) }) { first, _ in first }
        // Commit dates are set by whoever commits, so only the reviewed commit tells whether the head moved since.
        if let reviewedOid = viewerReview?.commit?.oid {
            facts.newCommitsSinceViewerReview = reviewedOid != pr.headRefOid
        }
        facts.ciStatus = lastCommit?.statusCheckRollup?.state
        // GitHub computes mergeability lazily and answers UNKNOWN in between, which would change the input for nothing.
        facts.hasMergeConflict = pr.mergeable == "CONFLICTING" ? true : nil
        facts.applyActivity(events, notification: notification)

        return ThreadContext(
            htmlURL: pr.url,
            facts: facts,
            untrusted: UntrustedContent(title: pr.title, body: pr.body.truncated(to: bodyLimit), recentActivity: recentActivity(events))
        )
    }

    static func issue(_ issue: IssueNode, notification: GitHubNotification, viewer: String) -> ThreadContext {
        var events = [Event(author: issue.author.displayLogin, kind: "opened", at: issue.createdAt, body: issue.body)]
        events += issue.comments.items.map { Event(author: $0.author.displayLogin, kind: "comment", at: $0.createdAt, body: $0.body) }

        var facts = Facts(notification, kind: "issue", viewer: viewer)
        facts.state = [issue.state, issue.stateReason].compactMap { $0?.lowercased() }.joined(separator: ":")
        facts.author = issue.author.displayLogin
        facts.viewerIsAuthor = issue.author.displayLogin == viewer
        facts.viewerIsAssignee = issue.assignees.items.contains { $0.displayLogin == viewer }
        facts.applyActivity(events, notification: notification)

        return ThreadContext(
            htmlURL: issue.url,
            facts: facts,
            untrusted: UntrustedContent(title: issue.title, body: issue.body.truncated(to: bodyLimit), recentActivity: recentActivity(events))
        )
    }

    static func advisory(_ advisory: Advisory?, notification: GitHubNotification, viewer: String) -> ThreadContext {
        guard let advisory else { return generic(notification, htmlURL: nil, viewer: viewer, kind: "security_advisory") }
        var facts = Facts(notification, kind: "security_advisory", viewer: viewer)
        facts.state = advisory.state
        facts.severity = advisory.severity
        facts.author = advisory.author?.login
        facts.viewerIsAuthor = advisory.author?.login == viewer
        facts.viewerIsAdvisoryCollaborator = advisory.collaboratingUsers?.contains { $0.login == viewer } ?? false
        return ThreadContext(
            htmlURL: advisory.htmlUrl,
            facts: facts,
            untrusted: UntrustedContent(title: advisory.summary, body: advisory.description?.truncated(to: bodyLimit))
        )
    }

    static func generic(_ notification: GitHubNotification, htmlURL: URL?, viewer: String, kind: String? = nil) -> ThreadContext {
        ThreadContext(
            htmlURL: htmlURL ?? notification.repository.htmlUrl,
            facts: Facts(notification, kind: kind ?? notification.subject.type, viewer: viewer),
            untrusted: UntrustedContent(title: notification.subject.title)
        )
    }

    private static func recentActivity(_ events: [Event]) -> [UntrustedContent.Entry] {
        events.dropFirst().sorted { $0.at < $1.at }.suffix(recentActivityLimit).map {
            UntrustedContent.Entry(author: $0.author, kind: $0.kind, at: $0.at, path: $0.path, body: $0.body.truncated(to: entryLimit))
        }
    }
}

struct Event {
    let author: String
    let kind: String
    let at: Date
    let body: String
    var path: String?
}

extension Facts {
    mutating func applyActivity(_ events: [Event], notification: GitHubNotification) {
        let viewerLastActivityAt = events.filter { $0.author == viewer }.map(\.at).max()
        let last = events.max { $0.at < $1.at }
        lastActivity = last.map { LastActivity(author: $0.author, kind: $0.kind, at: $0.at) }
        viewerWroteLastActivity = last?.author == viewer
        self.viewerLastActivityAt = viewerLastActivityAt
        activityCountSinceLastRead = events.filter { $0.at > (notification.lastReadAt ?? .distantPast) }.count
        viewerMentionedSinceViewerLastActivity = events.contains {
            $0.author != viewer && $0.at > (viewerLastActivityAt ?? .distantPast) && Self.mentions(viewer, in: $0.body)
        }
    }

    static func mentions(_ login: String, in text: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9-])@\(NSRegularExpression.escapedPattern(for: login))(?![A-Za-z0-9-])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension String {
    func truncated(to limit: Int) -> String {
        count > limit ? prefix(limit) + "…" : self
    }
}
