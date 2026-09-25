import Foundation

public struct TriageCache: Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let key: String
        public let fingerprint: String
        public let updatedAt: Date
        public let htmlURL: URL
        public let triage: Triage
        public var details: String?

        public init(key: String, fingerprint: String, updatedAt: Date, htmlURL: URL, triage: Triage, details: String? = nil) {
            self.key = key
            self.fingerprint = fingerprint
            self.updatedAt = updatedAt
            self.htmlURL = htmlURL
            self.triage = triage
            self.details = details
        }

        public func isFresh(for notification: GitHubNotification, fingerprint: String) -> Bool {
            updatedAt == notification.updatedAt && self.fingerprint == fingerprint
        }
    }

    public private(set) var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Atbang/triage-cache.json")
    }

    public static func load(from url: URL) -> TriageCache {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return TriageCache() }
        return TriageCache(entries: entries)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    public subscript(threadID: String) -> Entry? {
        get { entries[threadID] }
        set { entries[threadID] = newValue }
    }

    public mutating func prune(keeping threadIDs: Set<String>) {
        entries = entries.filter { threadIDs.contains($0.key) }
    }
}
