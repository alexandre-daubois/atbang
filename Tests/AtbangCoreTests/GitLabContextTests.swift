import Foundation
@testable import AtbangCore
import Testing

private struct FixedContexts: ContextProviding {
    let htmlURL: URL

    func context(for notification: GitHubNotification) async throws -> ThreadContext {
        .generic(notification, htmlURL: htmlURL, viewer: "alice")
    }
}

struct GitLabContextTests {
    @Test func mergeRequestAwaitingViewerReview() {
        let context = ThreadContext.mergeRequest(Fixtures.gitLabGraphQL(Fixtures.mergeRequest), notification: Fixtures.gitLabNotification(), viewer: "alice")
        let facts = context.facts

        #expect(context.htmlURL.absoluteString == "https://gitlab.example.com/o/r/-/merge_requests/7")
        #expect(facts.kind == "merge_request")
        #expect(facts.repository == "o/r")
        #expect(facts.number == 7)
        #expect(facts.state == "opened")
        #expect(facts.isDraft == false)
        #expect(facts.viewerIsAuthor == false)
        #expect(facts.reviewRequestedFromViewer == true)
        #expect(facts.latestReviewByReviewer == ["carol": "APPROVED"])
        #expect(facts.ciStatus == "SUCCESS")
        #expect(facts.hasMergeConflict == nil)
        #expect(facts.lastActivity == Facts.LastActivity(author: "ghost", kind: "comment", at: Fixtures.date("2026-09-22T11:00:00Z")))
        #expect(facts.viewerMentionedSinceViewerLastActivity == true)
        #expect(context.untrusted.body == "Please have a look")
        #expect(context.untrusted.recentActivity?.map(\.kind) == ["review_comment", "system_note", "comment"])
        #expect(context.untrusted.recentActivity?.first?.path == "a.swift")
    }

    @Test func ownDraftWithConflictAndFailedPipelineAfterViewerPushed() {
        let notification = Fixtures.gitLabNotification(url: "https://gitlab.example.com/o/r/-/merge_requests/10")
        let context = ThreadContext.mergeRequest(Fixtures.gitLabGraphQL(Fixtures.ownMergeRequestWithConflict), notification: notification, viewer: "alice.smith")
        let facts = context.facts

        #expect(facts.isDraft == true)
        #expect(facts.viewerIsAuthor == true)
        #expect(facts.viewerIsAssignee == true)
        #expect(facts.reviewRequestedFromViewer == false)
        #expect(facts.latestReviewByReviewer == ["carol": "REQUESTED_CHANGES"])
        #expect(facts.ciStatus == "FAILED")
        #expect(facts.hasMergeConflict == true)
        #expect(facts.viewerWroteLastActivity == true)
        #expect(context.untrusted.body == nil)
    }

    @Test(arguments: [
        ("UNREVIEWED", true),
        ("REVIEW_STARTED", true),
        ("REVIEWED", false),
        ("APPROVED", false),
        ("REQUESTED_CHANGES", false),
    ])
    func onlyAnUnfinishedReviewIsStillRequested(state: String, requested: Bool) {
        let json = Fixtures.mergeRequest.replacingOccurrences(of: #"{"reviewState":"UNREVIEWED"}"#, with: #"{"reviewState":"\#(state)"}"#)
        let facts = ThreadContext.mergeRequest(Fixtures.gitLabGraphQL(json), notification: Fixtures.gitLabNotification(), viewer: "alice").facts

        #expect(facts.reviewRequestedFromViewer == requested)
    }

    @Test func viewerWhoIsNotAReviewerIsNotRequested() {
        let facts = ThreadContext.mergeRequest(Fixtures.gitLabGraphQL(Fixtures.mergeRequest), notification: Fixtures.gitLabNotification(), viewer: "erin").facts

        #expect(facts.reviewRequestedFromViewer == false)
    }

    @Test func issueQuestionForSomeoneElse() {
        let notification = Fixtures.gitLabNotification(type: "Issue", url: "https://gitlab.example.com/o/r/-/work_items/9")
        let context = ThreadContext.gitLabIssue(Fixtures.gitLabGraphQL(Fixtures.gitLabIssue), notification: notification, viewer: "alice")

        #expect(context.htmlURL.absoluteString == "https://gitlab.example.com/o/r/-/work_items/9")
        #expect(context.facts.kind == "issue")
        #expect(context.facts.number == 9)
        #expect(context.facts.state == "closed")
        #expect(context.facts.viewerIsAssignee == true)
        #expect(context.facts.viewerMentionedSinceViewerLastActivity == false)
        #expect(context.untrusted.recentActivity?.map(\.author) == ["erin"])
    }

    @Test func otherTargetsLinkToTheirPageWithoutGlab() async throws {
        let notification = Fixtures.gitLabNotification(type: "Commit", url: "https://gitlab.example.com/o/r/-/commit/abc")
        let provider = GitLabContextProvider(client: GitLabClient(glab: URL(filePath: "/nonexistent/glab"), host: "gitlab.example.com"), viewer: "alice")

        let context = try await provider.context(for: notification)

        #expect(context.htmlURL.absoluteString == "https://gitlab.example.com/o/r/-/commit/abc")
        #expect(context.facts.kind == "Commit")
        #expect(context.untrusted == UntrustedContent(title: "Add feature"))
    }

    @Test func forgeProviderPicksTheNotificationsForge() async throws {
        let provider = ForgeContextProvider([
            .github: FixedContexts(htmlURL: URL(string: "https://github.com/o/r")!),
            .gitlab: FixedContexts(htmlURL: URL(string: "https://gitlab.example.com/o/r")!),
        ])

        #expect(try await provider.context(for: Fixtures.notification()).htmlURL.host() == "github.com")
        #expect(try await provider.context(for: Fixtures.gitLabNotification()).htmlURL.host() == "gitlab.example.com")
    }

    @Test func forgeProviderRefusesATurnedOffForge() async {
        let provider = ForgeContextProvider([.github: FixedContexts(htmlURL: URL(string: "https://github.com/o/r")!)])

        await #expect(throws: ForgeContextProvider.Unavailable.self) {
            try await provider.context(for: Fixtures.gitLabNotification())
        }
    }
}
