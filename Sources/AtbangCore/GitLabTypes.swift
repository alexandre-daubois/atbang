import Foundation

enum GitLabQueries {
    static let mergeRequest = """
    query($fullPath: ID!, $iid: String!) {
      project(fullPath: $fullPath) {
        mergeRequest(iid: $iid) {
          webUrl title description state draft createdAt conflicts
          author { username }
          assignees { nodes { username } }
          reviewers { nodes { username mergeRequestInteraction { reviewState } } }
          headPipeline { status }
          notes(last: 50) { nodes { author { username } createdAt body system position { filePath } } }
        }
      }
    }
    """

    static let issue = """
    query($fullPath: ID!, $iid: String!) {
      project(fullPath: $fullPath) {
        issue(iid: $iid) {
          webUrl title description state createdAt
          author { username }
          assignees { nodes { username } }
          notes(last: 50) { nodes { author { username } createdAt body system position { filePath } } }
        }
      }
    }
    """
}

struct GitLabUser: Decodable, Sendable {
    let username: String
}

extension GitLabUser? {
    var displayUsername: String {
        self?.username ?? "ghost"
    }
}

struct GitLabNote: Decodable, Sendable {
    struct Position: Decodable, Sendable { let filePath: String? }
    let author: GitLabUser?
    let createdAt: Date
    let body: String
    let system: Bool
    let position: Position?

    var event: Event {
        let kind = system ? "system_note" : position?.filePath == nil ? "comment" : "review_comment"
        return Event(author: author.displayUsername, kind: kind, at: createdAt, body: body, path: position?.filePath)
    }
}

struct MergeRequestData: Decodable, Sendable {
    struct Project: Decodable, Sendable { let mergeRequest: MergeRequestNode? }
    let project: Project?
}

struct GitLabIssueData: Decodable, Sendable {
    struct Project: Decodable, Sendable { let issue: GitLabIssueNode? }
    let project: Project?
}

struct MergeRequestNode: Decodable, Sendable {
    struct Reviewer: Decodable, Sendable {
        struct Interaction: Decodable, Sendable { let reviewState: String }
        let username: String
        let mergeRequestInteraction: Interaction?
    }

    struct Pipeline: Decodable, Sendable { let status: String }

    let webUrl: URL
    let title: String
    let description: String?
    let state: String
    let draft: Bool
    let createdAt: Date
    let conflicts: Bool
    let author: GitLabUser?
    let assignees: Nodes<GitLabUser>
    let reviewers: Nodes<Reviewer>
    let headPipeline: Pipeline?
    let notes: Nodes<GitLabNote>
}

struct GitLabIssueNode: Decodable, Sendable {
    let webUrl: URL
    let title: String
    let description: String?
    let state: String
    let createdAt: Date
    let author: GitLabUser?
    let assignees: Nodes<GitLabUser>
    let notes: Nodes<GitLabNote>
}
