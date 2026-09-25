import Foundation

/// Every request goes through `send`, which only lets GET calls, GraphQL queries (never mutations) and marking one
/// notification thread as done reach api.github.com.
public struct GitHubClient: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAllowed
        case http(Int, String)
        case graphQL(String)
        case token(String)

        public var description: String {
            switch self {
            case .notAllowed: "Refused a request other than a read or Mark as Done"
            case let .http(status, message): "GitHub answered \(status): \(message)"
            case let .graphQL(message): "GitHub GraphQL error: \(message)"
            case let .token(message): "Cannot read the gh token: \(message)"
            }
        }
    }

    private static let api = URL(string: "https://api.github.com")!

    static let restDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let graphQLDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession? = nil) {
        self.token = token
        self.session = session ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }()
    }

    public static func token(gh: URL) async throws -> String {
        let output = try await ProcessRunner.run(gh, arguments: ["auth", "token", "--hostname", "github.com"], timeout: .seconds(20))
        let token = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !token.isEmpty else { throw Failure.token(output.stderrText) }
        return token
    }

    public func viewerLogin() async throws -> String {
        struct User: Decodable { let login: String }
        return try await get(Self.api.appending(path: "user"), as: User.self).login
    }

    public struct UnreadNotifications: Sendable, Equatable {
        /// Nil when GitHub answered 304 Not Modified, which does not count against the rate limit.
        public let notifications: [GitHubNotification]?
        public let etag: String?
        public let pollInterval: Int?
    }

    /// Pages are offsets into a list sorted by activity, so a thread updated between two requests shows up twice.
    /// The ETag, unlike Last-Modified, also changes when a thread leaves the list after being read elsewhere.
    public func unreadNotifications(ifNoneMatch etag: String? = nil) async throws -> UnreadNotifications {
        var request = URLRequest(url: Self.api.appending(path: "notifications").appending(queryItems: [URLQueryItem(name: "per_page", value: "50")]))
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        let (notifications, response) = try await getAll(request, as: GitHubNotification.self)
        var seen = Set<String>()
        return UnreadNotifications(
            notifications: response.statusCode == 304 ? nil : notifications.filter { seen.insert($0.id).inserted },
            etag: response.value(forHTTPHeaderField: "ETag") ?? etag,
            pollInterval: response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap { Int($0) }
        )
    }

    /// A new comment does not bump an advisory's `updated_at`, so the one a notification points to can sit on any page.
    public func advisories(in repository: String) async throws -> [Advisory] {
        let url = Self.api.appending(path: "repos/\(repository)/security-advisories").appending(queryItems: [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
        ])
        return try await getAll(URLRequest(url: url), as: Advisory.self).items
    }

    public func markAsDone(threadID: String) async throws {
        var request = URLRequest(url: Self.api.appending(path: "notifications/threads/\(threadID)"))
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    public func htmlURL(of resource: URL) async throws -> URL? {
        struct Resource: Decodable { let htmlUrl: URL? }
        return try await get(resource, as: Resource.self).htmlUrl
    }

    public func query<Variables: Encodable & Sendable, T: Decodable>(_ query: String, variables: Variables, as _: T.Type) async throws -> T {
        var request = URLRequest(url: Self.api.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(GraphQLPayload(query: query, variables: variables))
        let response = try Self.graphQLDecoder.decode(GraphQLResponse<T>.self, from: await send(request).data)
        guard let data = response.data else {
            throw Failure.graphQL(response.errors?.map(\.message).joined(separator: "; ") ?? "no data")
        }
        return data
    }

    private func get<T: Decodable>(_ url: URL, as _: T.Type) async throws -> T {
        try Self.restDecoder.decode(T.self, from: await send(URLRequest(url: url)).data)
    }

    private func getAll<T: Decodable>(_ request: URLRequest, as _: T.Type) async throws -> (items: [T], first: HTTPURLResponse) {
        let (data, first) = try await send(request)
        guard first.statusCode != 304 else { return ([], first) }
        var items = try Self.restDecoder.decode([T].self, from: data)
        var next = Self.nextPage(in: first.value(forHTTPHeaderField: "Link"))
        while let url = next {
            let (data, response) = try await send(URLRequest(url: url))
            items += try Self.restDecoder.decode([T].self, from: data)
            next = Self.nextPage(in: response.value(forHTTPHeaderField: "Link"))
        }
        return (items, first)
    }

    static func nextPage(in link: String?) -> URL? {
        link?.split(separator: ",").lazy.compactMap { entry -> URL? in
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.dropFirst().contains(#"rel="next""#) else { return nil }
            return URL(string: parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
        }.first
    }

    private func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        guard Self.isAllowed(request) else { throw Failure.notAllowed }
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) || response.statusCode == 304 else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (data, response)
    }

    static func isAllowed(_ request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "https", url.host() == "api.github.com" else { return false }
        switch request.httpMethod {
        case "GET":
            return true
        case "DELETE":
            // `/notifications/threads/{id}/subscription` would unsubscribe, so only the bare thread path passes.
            return url.query() == nil && url.path().wholeMatch(of: /\/notifications\/threads\/[0-9]+/) != nil
        case "POST":
            struct Payload: Decodable { let query: String }
            guard url.path() == "/graphql", let body = request.httpBody,
                  let payload = try? JSONDecoder().decode(Payload.self, from: body) else { return false }
            return payload.query.range(of: #"\bmutation\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        default:
            return false
        }
    }
}

private struct GraphQLPayload<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    struct Message: Decodable { let message: String }
    let data: T?
    let errors: [Message]?
}
