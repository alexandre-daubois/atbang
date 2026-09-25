import Foundation
@testable import AtbangCore

enum Fixtures {
    static func notificationJSON(
        id: String = "1",
        type: String = "PullRequest",
        url: String? = "https://api.github.com/repos/o/r/pulls/7",
        title: String = "Add feature",
        reason: String = "review_requested",
        updatedAt: String = "2026-09-22T12:00:00Z",
        lastReadAt: String? = nil
    ) -> String {
        """
        {"id":"\(id)","unread":true,"reason":"\(reason)","updated_at":"\(updatedAt)",
         "last_read_at":\(lastReadAt.map { "\"\($0)\"" } ?? "null"),
         "subject":{"title":"\(title)","url":\(url.map { "\"\($0)\"" } ?? "null"),"latest_comment_url":null,"type":"\(type)"},
         "repository":{"full_name":"o/r","html_url":"https://github.com/o/r"}}
        """
    }

    static func notification(
        id: String = "1",
        type: String = "PullRequest",
        url: String? = "https://api.github.com/repos/o/r/pulls/7",
        title: String = "Add feature",
        updatedAt: String = "2026-09-22T12:00:00Z",
        lastReadAt: String? = nil
    ) -> GitHubNotification {
        let json = notificationJSON(id: id, type: type, url: url, title: title, updatedAt: updatedAt, lastReadAt: lastReadAt)
        return try! GitHubClient.restDecoder.decode(GitHubNotification.self, from: Data(json.utf8))
    }

    static func gitLabTodoJSON(
        id: Int = 1,
        type: String = "MergeRequest",
        url: String = "https://gitlab.example.com/o/r/-/merge_requests/7",
        targetUpdatedAt: String = "2026-09-22T12:00:00.000Z"
    ) -> String {
        """
        {"id":\(id),"project":{"id":3,"path_with_namespace":"o/r"},"author":{"username":"bob"},"action_name":"review_requested",\
        "target_type":"\(type)","target":{"iid":7,"title":"Add feature","updated_at":"\(targetUpdatedAt)"},"target_url":"\(url)",\
        "body":"Add feature","state":"pending","created_at":"2026-09-21T10:00:00.123Z","updated_at":"2026-09-21T10:00:00.123Z"}
        """
    }

    static func gitLabNotification(type: String = "MergeRequest", url: String = "https://gitlab.example.com/o/r/-/merge_requests/7") -> GitHubNotification {
        try! GitLabClient.restDecoder.decode(GitLabTodo.self, from: Data(gitLabTodoJSON(type: type, url: url).utf8)).notification
    }

    static func gitLabGraphQL<T: Decodable>(_ json: String, as _: T.Type = T.self) -> T {
        try! GitLabClient.graphQLDecoder.decode(T.self, from: Data(json.utf8))
    }

    static func graphQL<T: Decodable>(_ json: String, as _: T.Type = T.self) -> T {
        try! GitHubClient.graphQLDecoder.decode(T.self, from: Data(json.utf8))
    }

    static func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    static let pullRequest = """
    {"url":"https://github.com/o/r/pull/7","title":"Add feature","body":"Please have a look","state":"OPEN","isDraft":false,
     "merged":false,"createdAt":"2026-09-20T10:00:00Z","reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE","headRefOid":"abc",
     "author":{"__typename":"User","login":"bob"},
     "assignees":{"nodes":[]},
     "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"alice"}},{"requestedReviewer":{"__typename":"Team","combinedSlug":"o/core"}},null]},
     "latestReviews":{"nodes":[{"author":{"__typename":"User","login":"carol"},"state":"APPROVED","submittedAt":"2026-09-21T10:00:00Z","commit":{"oid":"abc"}}]},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-09-20T09:00:00Z","author":{"user":{"login":"bob"}},"statusCheckRollup":{"state":"SUCCESS"}}}]},
     "comments":{"nodes":[
       {"author":{"__typename":"Bot","login":"codecov"},"createdAt":"2026-09-20T11:00:00Z","body":"Coverage 90%"},
       {"author":null,"createdAt":"2026-09-22T11:00:00Z","body":"@alice what do you think?"}]},
     "reviews":{"nodes":[
       {"author":{"__typename":"User","login":"carol"},"state":"APPROVED","submittedAt":"2026-09-21T10:00:00Z","body":"",
        "comments":{"nodes":[{"author":{"__typename":"User","login":"carol"},"createdAt":"2026-09-21T09:59:00Z","body":"nit","path":"a.swift"}]}},
       {"author":{"__typename":"User","login":"alice"},"state":"PENDING","submittedAt":null,"body":"my draft","comments":{"nodes":[]}}]}}
    """

    static let ownMergedPullRequest = """
    {"url":"https://github.com/o/r/pull/8","title":"Fix","body":"","state":"MERGED","isDraft":false,
     "merged":true,"createdAt":"2026-09-20T10:00:00Z","reviewDecision":"APPROVED","mergeable":"UNKNOWN","headRefOid":"def2",
     "author":{"__typename":"User","login":"alice"},
     "assignees":{"nodes":[{"__typename":"User","login":"alice"}]},
     "reviewRequests":{"nodes":[]},
     "latestReviews":{"nodes":[{"author":{"__typename":"User","login":"alice"},"state":"COMMENTED","submittedAt":"2026-09-20T12:00:00Z","commit":{"oid":"def1"}}]},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-09-21T09:00:00Z","author":{"user":{"login":"alice"}},"statusCheckRollup":null}}]},
     "comments":{"nodes":[
       {"author":{"__typename":"User","login":"bob"},"createdAt":"2026-09-21T11:00:00Z","body":"@alice thanks"},
       {"author":{"__typename":"User","login":"alice"},"createdAt":"2026-09-22T11:00:00Z","body":"You're welcome @bob"}]},
     "reviews":{"nodes":[]}}
    """

    static let ownPullRequestPushedAfterReview = """
    {"url":"https://github.com/o/r/pull/10","title":"Refactor","body":"","state":"OPEN","isDraft":false,
     "merged":false,"createdAt":"2026-09-20T10:00:00Z","reviewDecision":"CHANGES_REQUESTED","mergeable":"CONFLICTING","headRefOid":"new",
     "author":{"__typename":"User","login":"alice"},
     "assignees":{"nodes":[]},
     "reviewRequests":{"nodes":[]},
     "latestReviews":{"nodes":[{"author":{"__typename":"User","login":"carol"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-21T10:00:00Z","commit":{"oid":"old"}}]},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-09-21T12:00:00Z","author":{"user":{"login":"alice"}},"statusCheckRollup":{"state":"FAILURE"}}}]},
     "comments":{"nodes":[]},
     "reviews":{"nodes":[{"author":{"__typename":"User","login":"carol"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-21T10:00:00Z","body":"Please split this","comments":{"nodes":[]}}]}}
    """

    static let issue = """
    {"url":"https://github.com/o/r/issues/9","title":"Crash","body":"It crashes","state":"CLOSED","stateReason":"NOT_PLANNED",
     "createdAt":"2026-09-20T10:00:00Z","author":{"__typename":"User","login":"dave"},
     "assignees":{"nodes":[{"__typename":"User","login":"alice"}]},
     "comments":{"nodes":[{"author":{"__typename":"User","login":"erin"},"createdAt":"2026-09-21T10:00:00Z","body":"@bob can you check?"}]}}
    """

    static let advisory = """
    {"ghsa_id":"GHSA-xxxx-yyyy-zzzz","summary":"Heap overflow in parser","description":"Details","state":"triage","severity":"high",
     "html_url":"https://github.com/o/r/security/advisories/GHSA-xxxx-yyyy-zzzz","author":{"login":"reporter"},
     "collaborating_users":[{"login":"alice"}]}
    """

    static let mergeRequest = """
    {"webUrl":"https://gitlab.example.com/o/r/-/merge_requests/7","title":"Add feature","description":"Please have a look","state":"opened",
     "draft":false,"createdAt":"2026-09-20T10:00:00Z","conflicts":false,
     "author":{"username":"bob"},
     "assignees":{"nodes":[]},
     "reviewers":{"nodes":[
       {"username":"alice","mergeRequestInteraction":{"reviewState":"UNREVIEWED"}},
       {"username":"carol","mergeRequestInteraction":{"reviewState":"APPROVED"}},
       {"username":"dave","mergeRequestInteraction":null}]},
     "headPipeline":{"status":"SUCCESS"},
     "notes":{"nodes":[
       {"author":{"username":"carol"},"createdAt":"2026-09-21T09:59:00Z","body":"nit","system":false,"position":{"filePath":"a.swift"}},
       {"author":{"username":"carol"},"createdAt":"2026-09-21T10:00:00Z","body":"approved this merge request","system":true,"position":null},
       {"author":null,"createdAt":"2026-09-22T11:00:00Z","body":"@alice what do you think?","system":false,"position":null}]}}
    """

    static let ownMergeRequestWithConflict = """
    {"webUrl":"https://gitlab.example.com/o/r/-/merge_requests/10","title":"Refactor","description":null,"state":"opened",
     "draft":true,"createdAt":"2026-09-20T10:00:00Z","conflicts":true,
     "author":{"username":"alice.smith"},
     "assignees":{"nodes":[{"username":"alice.smith"}]},
     "reviewers":{"nodes":[{"username":"carol","mergeRequestInteraction":{"reviewState":"REQUESTED_CHANGES"}}]},
     "headPipeline":{"status":"FAILED"},
     "notes":{"nodes":[
       {"author":{"username":"carol"},"createdAt":"2026-09-21T10:00:00Z","body":"Please split this","system":false,"position":null},
       {"author":{"username":"alice.smith"},"createdAt":"2026-09-21T12:00:00Z","body":"added 1 commit","system":true,"position":null}]}}
    """

    static let gitLabIssue = """
    {"webUrl":"https://gitlab.example.com/o/r/-/work_items/9","title":"Crash","description":"It crashes","state":"closed",
     "createdAt":"2026-09-20T10:00:00Z","author":{"username":"dave"},
     "assignees":{"nodes":[{"username":"alice"}]},
     "notes":{"nodes":[{"author":{"username":"erin"},"createdAt":"2026-09-21T10:00:00Z","body":"@bob can you check?","system":false,"position":null}]}}
    """
}
