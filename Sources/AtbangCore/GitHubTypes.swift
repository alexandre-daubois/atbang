import Foundation

struct ThreadVariables: Encodable, Sendable {
    let owner: String
    let name: String
    let number: Int
}

enum ThreadQueries {
    static let pullRequest = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          url title body state isDraft merged createdAt reviewDecision mergeable headRefOid
          author { __typename login }
          assignees(first: 20) { nodes { __typename login } }
          reviewRequests(first: 20) { nodes { requestedReviewer { __typename ... on User { login } ... on Team { combinedSlug } } } }
          latestReviews(first: 20) { nodes { author { __typename login } state submittedAt commit { oid } } }
          commits(last: 1) { nodes { commit { committedDate author { user { login } } statusCheckRollup { state } } } }
          comments(last: 30) { nodes { author { __typename login } createdAt body } }
          reviews(last: 20) {
            nodes {
              author { __typename login } state submittedAt body
              comments(last: 10) { nodes { author { __typename login } createdAt body path } }
            }
          }
        }
      }
    }
    """

    static let issue = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) {
          url title body state stateReason createdAt
          author { __typename login }
          assignees(first: 20) { nodes { __typename login } }
          comments(last: 30) { nodes { author { __typename login } createdAt body } }
        }
      }
    }
    """
}

struct Nodes<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]

    private enum CodingKeys: String, CodingKey { case nodes }

    init(from decoder: Decoder) throws {
        items = try decoder.container(keyedBy: CodingKeys.self).decode([T?].self, forKey: .nodes).compactMap { $0 }
    }
}

struct GraphQLActor: Decodable, Sendable {
    let typename: String
    let login: String

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login
    }

    var displayLogin: String {
        typename == "Bot" ? "\(login)[bot]" : login
    }
}

extension GraphQLActor? {
    /// GitHub returns a null author for deleted accounts and shows them as "ghost".
    var displayLogin: String {
        self?.displayLogin ?? "ghost"
    }
}

struct PullRequestData: Decodable, Sendable {
    struct Repository: Decodable, Sendable { let pullRequest: PullRequestNode? }
    let repository: Repository?
}

struct IssueData: Decodable, Sendable {
    struct Repository: Decodable, Sendable { let issue: IssueNode? }
    let repository: Repository?
}

struct PullRequestNode: Decodable, Sendable {
    struct ReviewRequest: Decodable, Sendable {
        struct Reviewer: Decodable, Sendable {
            let typename: String
            let login: String?
            let combinedSlug: String?

            private enum CodingKeys: String, CodingKey {
                case typename = "__typename"
                case login, combinedSlug
            }
        }

        let requestedReviewer: Reviewer?
    }

    struct LatestReview: Decodable, Sendable {
        struct Commit: Decodable, Sendable { let oid: String }
        let author: GraphQLActor?
        let state: String
        let submittedAt: Date?
        let commit: Commit?
    }

    struct CommitNode: Decodable, Sendable {
        struct Commit: Decodable, Sendable {
            struct Author: Decodable, Sendable {
                struct User: Decodable, Sendable { let login: String }
                let user: User?
            }

            struct Rollup: Decodable, Sendable { let state: String }
            let committedDate: Date
            let author: Author?
            let statusCheckRollup: Rollup?
        }

        let commit: Commit
    }

    struct Review: Decodable, Sendable {
        struct Comment: Decodable, Sendable {
            let author: GraphQLActor?
            let createdAt: Date
            let body: String
            let path: String?
        }

        let author: GraphQLActor?
        let state: String
        let submittedAt: Date?
        let body: String
        let comments: Nodes<Comment>
    }

    let url: URL
    let title: String
    let body: String
    let state: String
    let isDraft: Bool
    let merged: Bool
    let createdAt: Date
    let reviewDecision: String?
    let mergeable: String
    let headRefOid: String
    let author: GraphQLActor?
    let assignees: Nodes<GraphQLActor>
    let reviewRequests: Nodes<ReviewRequest>
    let latestReviews: Nodes<LatestReview>
    let commits: Nodes<CommitNode>
    let comments: Nodes<IssueComment>
    let reviews: Nodes<Review>
}

struct IssueComment: Decodable, Sendable {
    let author: GraphQLActor?
    let createdAt: Date
    let body: String
}

struct IssueNode: Decodable, Sendable {
    let url: URL
    let title: String
    let body: String
    let state: String
    let stateReason: String?
    let createdAt: Date
    let author: GraphQLActor?
    let assignees: Nodes<GraphQLActor>
    let comments: Nodes<IssueComment>
}

public struct Advisory: Decodable, Sendable {
    public struct User: Decodable, Sendable { public let login: String }

    public let summary: String
    public let description: String?
    public let state: String
    public let severity: String?
    public let htmlUrl: URL
    public let author: User?
    public let collaboratingUsers: [User]?
}
