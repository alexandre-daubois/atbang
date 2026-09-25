import Foundation

public enum Forge: String, Sendable {
    case github = "GitHub"
    case gitlab = "GitLab"
}

public struct GitHubNotification: Decodable, Sendable, Equatable, Identifiable {
    public struct Subject: Decodable, Sendable, Equatable {
        public let title: String
        public let url: URL?
        public let type: String
    }

    public struct Repository: Decodable, Sendable, Equatable {
        public let fullName: String
        public let htmlUrl: URL
    }

    public let id: String
    public let reason: String
    public let updatedAt: Date
    public let lastReadAt: Date?
    public let subject: Subject
    public let repository: Repository
    public var forge = Forge.github

    private enum CodingKeys: String, CodingKey {
        case id, reason, updatedAt, lastReadAt, subject, repository
    }

    public var number: Int? {
        guard let url = subject.url, ["issues", "pulls", "discussions", "merge_requests", "work_items"].contains(url.deletingLastPathComponent().lastPathComponent) else { return nil }
        return Int(url.lastPathComponent)
    }
}

public enum Priority: String, Codable, Sendable, Comparable, CaseIterable {
    case low, medium, high

    public var marks: String {
        switch self {
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public struct Triage: Codable, Sendable, Equatable {
    public let priority: Priority
    public let summary: String

    public init(priority: Priority, summary: String) {
        self.priority = priority
        self.summary = summary
    }
}

public struct TriageItem: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case pending
        case done
        case failed(String)
    }

    public enum Details: Sendable, Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }

    public let notification: GitHubNotification
    public var htmlURL: URL
    public var triage: Triage?
    public var status: Status
    public var details: Details?

    public var id: String { notification.id }

    public init(notification: GitHubNotification, triage: Triage?) {
        self.notification = notification
        // A GitLab to-do already points at the web page, a GitHub subject only at the API.
        htmlURL = (notification.forge == .gitlab ? notification.subject.url : nil) ?? notification.repository.htmlUrl
        self.triage = triage
        status = .pending
    }
}
