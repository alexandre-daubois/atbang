import Foundation
@testable import AtbangCore
import Testing

struct ThreadContextTests {
    @Test func pullRequestAwaitingViewerReview() {
        let context = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.pullRequest), notification: Fixtures.notification(), viewer: "alice")
        let facts = context.facts

        #expect(context.htmlURL.absoluteString == "https://github.com/o/r/pull/7")
        #expect(facts.kind == "pull_request")
        #expect(facts.number == 7)
        #expect(facts.state == "open")
        #expect(facts.viewerIsAuthor == false)
        #expect(facts.reviewRequestedFromViewer == true)
        #expect(facts.reviewRequestedFromTeams == ["o/core"])
        #expect(facts.latestReviewByReviewer == ["carol": "APPROVED"])
        #expect(facts.newCommitsSinceViewerReview == nil)
        #expect(facts.ciStatus == "SUCCESS")
        #expect(facts.lastActivity == Facts.LastActivity(author: "ghost", kind: "comment", at: Fixtures.date("2026-09-22T11:00:00Z")))
        #expect(facts.viewerWroteLastActivity == false)
        #expect(facts.viewerLastActivityAt == nil)
        #expect(facts.viewerMentionedSinceViewerLastActivity == true)
        #expect(facts.activityCountSinceLastRead == 5)
        #expect(facts.hasMergeConflict == nil)
    }

    @Test func pullRequestUntrustedContentKeepsBotsAndSkipsPendingReviews() {
        let context = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.pullRequest), notification: Fixtures.notification(), viewer: "alice")
        let activity = context.untrusted.recentActivity ?? []

        #expect(context.untrusted.title == "Add feature")
        #expect(activity.map(\.kind) == ["comment", "review_comment", "review_approved", "comment"])
        #expect(activity[0].author == "codecov[bot]")
        #expect(activity[1].path == "a.swift")
        #expect(!activity.contains { $0.body == "my draft" })
    }

    @Test func ownMergedPullRequestWhereViewerSpokeLast() {
        let notification = Fixtures.notification(lastReadAt: "2026-09-21T12:00:00Z")
        let facts = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.ownMergedPullRequest), notification: notification, viewer: "alice").facts

        #expect(facts.state == "merged")
        #expect(facts.viewerIsAuthor == true)
        #expect(facts.viewerIsAssignee == true)
        #expect(facts.reviewRequestedFromViewer == false)
        #expect(facts.reviewRequestedFromTeams == [])
        #expect(facts.newCommitsSinceViewerReview == true)
        #expect(facts.ciStatus == nil)
        #expect(facts.viewerWroteLastActivity == true)
        #expect(facts.viewerMentionedSinceViewerLastActivity == false)
        #expect(facts.activityCountSinceLastRead == 1)
    }

    @Test func viewerPushAfterChangesRequestedCountsAsTheirActivity() {
        let facts = ThreadContext.pullRequest(Fixtures.graphQL(Fixtures.ownPullRequestPushedAfterReview), notification: Fixtures.notification(), viewer: "alice").facts

        #expect(facts.lastActivity == Facts.LastActivity(author: "alice", kind: "commit", at: Fixtures.date("2026-09-21T12:00:00Z")))
        #expect(facts.viewerWroteLastActivity == true)
        #expect(facts.reviewDecision == "CHANGES_REQUESTED")
        #expect(facts.hasMergeConflict == true)
        #expect(facts.ciStatus == "FAILURE")
    }

    @Test func commitsWithoutAGitHubAuthorAreNotActivity() {
        let json = Fixtures.ownPullRequestPushedAfterReview.replacingOccurrences(of: #""author":{"user":{"login":"alice"}}"#, with: #""author":{"user":null}"#)
        let facts = ThreadContext.pullRequest(Fixtures.graphQL(json), notification: Fixtures.notification(), viewer: "alice").facts

        #expect(facts.lastActivity?.kind == "review_changes_requested")
        #expect(facts.viewerWroteLastActivity == false)
    }

    @Test func aCommitClaimingTheViewerOnSomeoneElsesPullRequestIsIgnored() {
        let json = Fixtures.pullRequest.replacingOccurrences(of: #""author":{"user":{"login":"bob"}}"#, with: #""author":{"user":{"login":"alice"}}"#)
            .replacingOccurrences(of: #""committedDate":"2026-09-20T09:00:00Z""#, with: #""committedDate":"2026-09-23T09:00:00Z""#)
        let context = ThreadContext.pullRequest(Fixtures.graphQL(json), notification: Fixtures.notification(), viewer: "alice")

        #expect(context.facts.viewerLastActivityAt == nil)
        #expect(context.facts.viewerWroteLastActivity == false)
        #expect(context.facts.viewerMentionedSinceViewerLastActivity == true)
        #expect(context.untrusted.recentActivity?.contains { $0.kind == "commit" } == false)
    }

    @Test func aFutureDatedCommitCannotOutliveTheNotification() {
        let json = Fixtures.ownPullRequestPushedAfterReview.replacingOccurrences(of: #""committedDate":"2026-09-21T12:00:00Z""#, with: #""committedDate":"2030-01-01T00:00:00Z""#)
        let notification = Fixtures.notification()
        let facts = ThreadContext.pullRequest(Fixtures.graphQL(json), notification: notification, viewer: "alice").facts

        #expect(facts.lastActivity == Facts.LastActivity(author: "alice", kind: "commit", at: notification.updatedAt))
    }

    @Test func issueQuestionForSomeoneElse() {
        let notification = Fixtures.notification(type: "Issue", url: "https://api.github.com/repos/o/r/issues/9")
        let context = ThreadContext.issue(Fixtures.graphQL(Fixtures.issue), notification: notification, viewer: "alice")

        #expect(context.facts.kind == "issue")
        #expect(context.facts.state == "closed:not_planned")
        #expect(context.facts.viewerIsAssignee == true)
        #expect(context.facts.viewerMentionedSinceViewerLastActivity == false)
        #expect(context.untrusted.recentActivity?.map(\.author) == ["erin"])
    }

    @Test func longBodiesAreTruncated() {
        let body = String(repeating: "a", count: ThreadContext.bodyLimit + 500)
        let json = Fixtures.issue.replacingOccurrences(of: "It crashes", with: body)
        let context = ThreadContext.issue(Fixtures.graphQL(json), notification: Fixtures.notification(type: "Issue"), viewer: "alice")

        #expect(context.untrusted.body?.count == ThreadContext.bodyLimit + 1)
        #expect(context.untrusted.body?.hasSuffix("…") == true)
    }

    @Test func recentActivityKeepsTheLatestEntriesTruncated() {
        let comments = (0..<25).map { index in
            #"{"author":{"__typename":"User","login":"u\#(index)"},"createdAt":"2026-09-21T10:\#(String(format: "%02d", index)):00Z","body":"\#(String(repeating: "b", count: ThreadContext.entryLimit + 10))"}"#
        }
        let json = Fixtures.issue.replacingOccurrences(
            of: #"{"author":{"__typename":"User","login":"erin"},"createdAt":"2026-09-21T10:00:00Z","body":"@bob can you check?"}"#,
            with: comments.joined(separator: ",")
        )
        let context = ThreadContext.issue(Fixtures.graphQL(json), notification: Fixtures.notification(type: "Issue"), viewer: "alice")
        let activity = context.untrusted.recentActivity ?? []

        #expect(activity.count == ThreadContext.recentActivityLimit)
        #expect(activity.first?.author == "u5")
        #expect(activity.last?.author == "u24")
        #expect(activity.allSatisfy { $0.body.count == ThreadContext.entryLimit + 1 })
        #expect(context.facts.activityCountSinceLastRead == 26)
    }

    @Test func matchedAdvisory() throws {
        let advisory = try GitHubClient.restDecoder.decode(Advisory.self, from: Data(Fixtures.advisory.utf8))
        let notification = Fixtures.notification(type: "RepositoryAdvisory", url: nil, title: "Heap overflow in parser")
        let context = ThreadContext.advisory(advisory, notification: notification, viewer: "alice")

        #expect(context.htmlURL.absoluteString == "https://github.com/o/r/security/advisories/GHSA-xxxx-yyyy-zzzz")
        #expect(context.facts.kind == "security_advisory")
        #expect(context.facts.state == "triage")
        #expect(context.facts.severity == "high")
        #expect(context.facts.author == "reporter")
        #expect(context.facts.viewerIsAdvisoryCollaborator == true)
        #expect(context.untrusted.body == "Details")
    }

    @Test func unmatchedAdvisoryFallsBackToRepository() {
        let notification = Fixtures.notification(type: "RepositoryAdvisory", url: nil, title: "Unknown")
        let context = ThreadContext.advisory(nil, notification: notification, viewer: "alice")

        #expect(context.htmlURL.absoluteString == "https://github.com/o/r")
        #expect(context.facts.kind == "security_advisory")
        #expect(context.facts.number == nil)
        #expect(context.facts.state == nil)
        #expect(context.untrusted == UntrustedContent(title: "Unknown"))
    }

    @Test(arguments: [
        ("@alice can you look?", true),
        ("thanks (@ALICE)", true),
        ("cc @alice.", true),
        ("@alice-bot please", false),
        ("@alicex please", false),
        ("mail me at bob@alice.com", false),
        ("no mention", false),
    ])
    func mentions(text: String, expected: Bool) {
        #expect(Facts.mentions("alice", in: text) == expected)
    }
}
