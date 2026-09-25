import Foundation

public struct GitLabContextProvider: ContextProviding {
    private let client: GitLabClient
    private let viewer: String

    public init(client: GitLabClient, viewer: String) {
        self.client = client
        self.viewer = viewer
    }

    public func context(for notification: GitHubNotification) async throws -> ThreadContext {
        guard let number = notification.number else { return .generic(notification, htmlURL: notification.subject.url, viewer: viewer) }
        let variables = ["fullPath": notification.repository.fullName, "iid": String(number)]
        switch notification.subject.type {
        case "MergeRequest":
            let data = try await client.query(GitLabQueries.mergeRequest, variables: variables, as: MergeRequestData.self)
            guard let mergeRequest = data.project?.mergeRequest else { throw GitLabClient.Failure.graphQL("merge request not found") }
            return .mergeRequest(mergeRequest, notification: notification, viewer: viewer)
        case "Issue":
            let data = try await client.query(GitLabQueries.issue, variables: variables, as: GitLabIssueData.self)
            guard let issue = data.project?.issue else { throw GitLabClient.Failure.graphQL("issue not found") }
            return .gitLabIssue(issue, notification: notification, viewer: viewer)
        default:
            return .generic(notification, htmlURL: notification.subject.url, viewer: viewer)
        }
    }
}

extension ThreadContext {
    static func mergeRequest(_ mr: MergeRequestNode, notification: GitHubNotification, viewer: String) -> ThreadContext {
        let events = [Event(author: mr.author.displayUsername, kind: "opened", at: mr.createdAt, body: mr.description ?? "")] + mr.notes.items.map(\.event)
        let reviewStates = Dictionary(mr.reviewers.items.compactMap { reviewer in
            reviewer.mergeRequestInteraction.map { (reviewer.username, $0.reviewState) }
        }) { first, _ in first }

        var facts = Facts(notification, kind: "merge_request", viewer: viewer)
        facts.state = mr.state
        facts.isDraft = mr.draft
        facts.author = mr.author.displayUsername
        facts.viewerIsAuthor = mr.author.displayUsername == viewer
        facts.viewerIsAssignee = mr.assignees.items.contains { $0.username == viewer }
        // GitLab keeps reviewers after they review, so only the ones who haven't finished are still requested.
        facts.reviewRequestedFromViewer = reviewStates[viewer] == "UNREVIEWED" || reviewStates[viewer] == "REVIEW_STARTED"
        facts.latestReviewByReviewer = reviewStates.filter { $0.value != "UNREVIEWED" }
        facts.ciStatus = mr.headPipeline?.status
        facts.hasMergeConflict = mr.conflicts ? true : nil
        facts.applyActivity(events, notification: notification)

        return ThreadContext(
            htmlURL: mr.webUrl,
            facts: facts,
            untrusted: UntrustedContent(title: mr.title, body: mr.description?.truncated(to: bodyLimit), recentActivity: recentActivity(events))
        )
    }

    static func gitLabIssue(_ issue: GitLabIssueNode, notification: GitHubNotification, viewer: String) -> ThreadContext {
        let events = [Event(author: issue.author.displayUsername, kind: "opened", at: issue.createdAt, body: issue.description ?? "")] + issue.notes.items.map(\.event)

        var facts = Facts(notification, kind: "issue", viewer: viewer)
        facts.state = issue.state
        facts.author = issue.author.displayUsername
        facts.viewerIsAuthor = issue.author.displayUsername == viewer
        facts.viewerIsAssignee = issue.assignees.items.contains { $0.username == viewer }
        facts.applyActivity(events, notification: notification)

        return ThreadContext(
            htmlURL: issue.webUrl,
            facts: facts,
            untrusted: UntrustedContent(title: issue.title, body: issue.description?.truncated(to: bodyLimit), recentActivity: recentActivity(events))
        )
    }
}
