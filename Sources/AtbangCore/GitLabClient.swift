import Foundation

/// Goes through `glab api`, so the token stays with glab and a self-hosted instance works as glab is configured.
public struct GitLabClient: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAllowed
        case timedOut
        case exit(Int32, String)
        case graphQL(String)

        public var description: String {
            switch self {
            case .notAllowed: "Refused a request other than a read or Mark as Done"
            case .timedOut: "glab timed out"
            case let .exit(status, message): "glab exited with \(status): \(message)"
            case let .graphQL(message): "GitLab GraphQL error: \(message)"
            }
        }
    }

    static let idPrefix = "gitlab:"

    static let restDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            try Date(decoder.singleValueContainer().decode(String.self), strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        return decoder
    }()

    static let graphQLDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public let glab: URL
    public let host: String

    public init(glab: URL, host: String) {
        self.glab = glab
        self.host = host
    }

    public func viewerUsername() async throws -> String {
        try Self.restDecoder.decode(GitLabUser.self, from: await api("user")).username
    }

    public func pendingTodos() async throws -> [GitHubNotification] {
        let lines = try await api("todos?state=pending&per_page=100", paginate: true).split(separator: UInt8(ascii: "\n"))
        let notifications = try lines.map { try Self.restDecoder.decode(GitLabTodo.self, from: Data($0)).notification }
        // Pages are offsets, so a to-do added between two requests can shift one onto the next page too.
        var seen = Set<String>()
        return notifications.filter { seen.insert($0.id).inserted }
    }

    public func markAsDone(_ notification: GitHubNotification) async throws {
        guard notification.id.hasPrefix(Self.idPrefix) else { throw Failure.notAllowed }
        _ = try await api("todos/\(notification.id.dropFirst(Self.idPrefix.count))/mark_as_done", method: "POST")
    }

    func query<T: Decodable>(_ query: String, variables: [String: String], as _: T.Type) async throws -> T {
        let data = try await api("graphql", method: "POST", fields: variables.merging(["query": query]) { $1 })
        let response = try Self.graphQLDecoder.decode(GraphQLResponse<T>.self, from: data)
        guard let data = response.data else {
            throw Failure.graphQL(response.errors?.map(\.message).joined(separator: "; ") ?? "no data")
        }
        return data
    }

    private func api(_ endpoint: String, method: String = "GET", paginate: Bool = false, fields: [String: String] = [:]) async throws -> Data {
        guard Self.isAllowed(endpoint: endpoint, method: method, fields: fields) else { throw Failure.notAllowed }
        var arguments = ["api", endpoint, "--hostname=\(host)", "--method=\(method)"]
        // With JSON output, glab 1.119 writes one array per page back to back.
        if paginate { arguments += ["--paginate", "--output=ndjson"] }
        arguments += fields.sorted { $0.key < $1.key }.flatMap { ["--raw-field", "\($0.key)=\($0.value)"] }
        // Inside a repository, glab would read the host and the `:placeholders` from it.
        let output = try await ProcessRunner.run(glab, arguments: arguments, currentDirectory: FileManager.default.temporaryDirectory)
        if output.timedOut { throw Failure.timedOut }
        guard output.status == 0 else { throw Failure.exit(output.status, String(output.stderrText.prefix(300))) }
        return output.stdout
    }

    static func isAllowed(endpoint: String, method: String, fields: [String: String]) -> Bool {
        // A colon would be a URL scheme or one of glab's `:placeholders`.
        guard !endpoint.contains(":") else { return false }
        switch method {
        case "GET":
            return fields.isEmpty
        case "POST" where endpoint == "graphql":
            guard let query = fields["query"] else { return false }
            return query.range(of: #"\bmutation\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        case "POST":
            return fields.isEmpty && endpoint.wholeMatch(of: /todos\/[0-9]+\/mark_as_done/) != nil
        default:
            return false
        }
    }
}

struct GitLabTodo: Decodable {
    struct Project: Decodable { let pathWithNamespace: String }

    struct Target: Decodable {
        let title: String?
        let updatedAt: Date?
    }

    let id: Int
    let project: Project?
    let actionName: String
    let targetType: String
    let target: Target?
    let targetUrl: URL
    let body: String?
    let updatedAt: Date

    var notification: GitHubNotification {
        let repository = URL(string: targetUrl.absoluteString.components(separatedBy: "/-/")[0]) ?? targetUrl
        return GitHubNotification(
            id: GitLabClient.idPrefix + String(id),
            reason: actionName,
            // The to-do keeps the date of the event that created it, only its target moves with later activity.
            updatedAt: max(updatedAt, target?.updatedAt ?? updatedAt),
            lastReadAt: nil,
            subject: .init(title: target?.title ?? body ?? targetType, url: targetUrl, type: targetType),
            repository: .init(fullName: project?.pathWithNamespace ?? String(repository.path().dropFirst()), htmlUrl: repository),
            forge: .gitlab
        )
    }
}
