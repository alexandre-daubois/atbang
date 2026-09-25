import Foundation
@testable import AtbangCore
import Testing

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, String) = { _ in (200, "[]") }
    nonisolated(unsafe) static var headers: (URLRequest) -> [String: String] = { _ in [:] }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers(request))!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct GitHubClientTests {
    private func client(
        headers: @escaping (URLRequest) -> [String: String] = { _ in [:] },
        _ respond: @escaping (URLRequest) -> (Int, String)
    ) -> GitHubClient {
        StubProtocol.requests = []
        StubProtocol.respond = respond
        StubProtocol.headers = headers
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return GitHubClient(token: "secret", session: URLSession(configuration: configuration))
    }

    private static func page(of request: URLRequest) -> String {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1"
    }

    private static func json(ids: [String]) -> String {
        "[" + ids.map { Fixtures.notificationJSON(id: $0) }.joined(separator: ",") + "]"
    }

    @Test func unreadNotificationsFollowTheLinkHeaderAndDropRepeatedThreads() async throws {
        let client = client(headers: { request in
            Self.page(of: request) == "1" ? ["Link": #"<https://api.github.com/notifications?per_page=50&page=2>; rel="next", <https://api.github.com/notifications?per_page=50&page=2>; rel="last""#] : [:]
        }) { request in
            Self.page(of: request) == "1" ? (200, Self.json(ids: (0..<50).map { "a\($0)" })) : (200, Self.json(ids: ["a49", "b0", "b1"]))
        }

        let notifications = try #require(try await client.unreadNotifications().notifications)

        #expect(notifications.count == 52)
        #expect(notifications.map(\.id).suffix(3) == ["a49", "b0", "b1"])
        #expect(StubProtocol.requests.count == 2)
        #expect(StubProtocol.requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
        #expect(StubProtocol.requests.allSatisfy { $0.url?.query()?.contains("all=") == false })
    }

    @Test func unchangedNotificationsCostNothing() async throws {
        let client = client(headers: { request in
            ["ETag": #""abc""#, "X-Poll-Interval": "120"]
        }) { request in
            request.value(forHTTPHeaderField: "If-None-Match") == #"W/"abc""# ? (304, "") : (200, Self.json(ids: ["1"]))
        }

        let unread = try await client.unreadNotifications(ifNoneMatch: #"W/"abc""#)

        #expect(unread == GitHubClient.UnreadNotifications(notifications: nil, etag: #""abc""#, pollInterval: 120))
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func changedNotificationsComeBackWithTheirETag() async throws {
        let client = client(headers: { _ in ["ETag": #"W/"new""#] }) { _ in (200, Self.json(ids: ["1", "2"])) }

        let unread = try await client.unreadNotifications(ifNoneMatch: #"W/"old""#)

        #expect(unread.notifications?.map(\.id) == ["1", "2"])
        #expect(unread.etag == #"W/"new""#)
        #expect(unread.pollInterval == nil)
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == #"W/"old""#)
    }

    @Test func aFirstRefreshSendsNoETag() async throws {
        let client = client { _ in (200, Self.json(ids: ["1"])) }

        _ = try await client.unreadNotifications()

        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func advisoriesAreReadAcrossCursorPages() async throws {
        let advisory = { (summary: String) in Fixtures.advisory.replacingOccurrences(of: "Heap overflow in parser", with: summary) }
        let client = client(headers: { request in
            request.url?.query()?.contains("after=") == true ? [:] : ["Link": #"<https://api.github.com/repos/o/r/security-advisories?per_page=100&after=Y3Vyc29y>; rel="next""#]
        }) { request in
            (200, "[" + advisory(request.url?.query()?.contains("after=") == true ? "Second page" : "First page") + "]")
        }

        let advisories = try await client.advisories(in: "o/r")

        #expect(advisories.map(\.summary) == ["First page", "Second page"])
        #expect(StubProtocol.requests.last?.url?.absoluteString == "https://api.github.com/repos/o/r/security-advisories?per_page=100&after=Y3Vyc29y")
    }

    @Test func aNextLinkOutsideTheAPIIsRefused() async {
        let client = client(headers: { _ in ["Link": #"<https://evil.example/notifications?page=2>; rel="next""#] }) { _ in (200, Self.json(ids: ["1"])) }

        await #expect(throws: GitHubClient.Failure.notAllowed) {
            try await client.unreadNotifications()
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test(arguments: [
        (#"<https://api.github.com/n?page=2>; rel="next", <https://api.github.com/n?page=5>; rel="last""#, "https://api.github.com/n?page=2"),
        (#"<https://api.github.com/n?page=1>; rel="prev", <https://api.github.com/n?page=3>; rel="next""#, "https://api.github.com/n?page=3"),
        (#"<https://api.github.com/n?page=1>; rel="first", <https://api.github.com/n?page=4>; rel="prev""#, nil),
        (nil, nil),
    ] as [(String?, String?)])
    func nextPage(link: String?, expected: String?) {
        #expect(GitHubClient.nextPage(in: link)?.absoluteString == expected)
    }

    @Test func httpErrorsSurfaceTheStatus() async {
        let client = client { _ in (401, #"{"message":"Bad credentials"}"#) }

        await #expect(throws: GitHubClient.Failure.http(401, #"{"message":"Bad credentials"}"#)) {
            try await client.viewerLogin()
        }
    }

    @Test func graphQLErrorsWithoutDataThrow() async {
        struct Variables: Encodable, Sendable { let number: Int }
        struct Empty: Decodable {}
        let client = client { _ in (200, #"{"data":null,"errors":[{"message":"Could not resolve"}]}"#) }

        await #expect(throws: GitHubClient.Failure.graphQL("Could not resolve")) {
            try await client.query("query { viewer { login } }", variables: Variables(number: 1), as: Empty.self)
        }
    }

    @Test func mutationsNeverReachTheNetwork() async {
        struct Variables: Encodable, Sendable { let id: String }
        struct Empty: Decodable {}
        let client = client { _ in (200, #"{"data":{}}"#) }

        await #expect(throws: GitHubClient.Failure.notAllowed) {
            try await client.query("mutation { markNotificationAsRead(input: {id: $id}) { success } }", variables: Variables(id: "1"), as: Empty.self)
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func markAsDoneDeletesTheThread() async throws {
        let client = client { _ in (204, "") }

        try await client.markAsDone(threadID: "25131771510")

        #expect(StubProtocol.requests.map(\.httpMethod) == ["DELETE"])
        #expect(StubProtocol.requests.first?.url?.absoluteString == "https://api.github.com/notifications/threads/25131771510")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test func markAsDoneSurfacesGitHubErrors() async {
        let client = client { _ in (404, #"{"message":"Not Found"}"#) }

        await #expect(throws: GitHubClient.Failure.http(404, #"{"message":"Not Found"}"#)) {
            try await client.markAsDone(threadID: "1")
        }
    }

    @Test func markAsDoneRefusesAnythingButAThreadID() async {
        let client = client { _ in (204, "") }

        await #expect(throws: GitHubClient.Failure.notAllowed) {
            try await client.markAsDone(threadID: "1/subscription")
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func tokenIsNeverSentOutsideTheAPI() async {
        let client = client { _ in (200, "{}") }

        await #expect(throws: GitHubClient.Failure.notAllowed) {
            try await client.htmlURL(of: URL(string: "https://evil.example/repos/o/r/releases/1")!)
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test(arguments: [
        ("GET", "https://api.github.com/notifications", nil, true),
        ("POST", "https://api.github.com/graphql", #"{"query":"query { viewer { login } }"}"#, true),
        ("POST", "https://api.github.com/graphql", #"{"query":"mutation { addStar(input: {}) { clientMutationId } }"}"#, false),
        ("POST", "https://api.github.com/graphql", #"{"query":"query A { a } Mutation B { b }"}"#, false),
        ("POST", "https://api.github.com/graphql", "not json", false),
        ("POST", "https://api.github.com/repos/o/r/issues", #"{"query":"query { a }"}"#, false),
        ("PATCH", "https://api.github.com/notifications/threads/1", nil, false),
        ("PUT", "https://api.github.com/notifications", nil, false),
        ("DELETE", "https://api.github.com/notifications/threads/1/subscription", nil, false),
        ("DELETE", "https://api.github.com/notifications/threads/25131771510", nil, true),
        ("DELETE", "https://api.github.com/notifications/threads/25131771510?x=1", nil, false),
        ("DELETE", "https://api.github.com/notifications/threads/abc", nil, false),
        ("DELETE", "https://api.github.com/notifications/threads/1%2Fsubscription", nil, false),
        ("DELETE", "https://api.github.com/notifications", nil, false),
        ("DELETE", "https://api.github.com/repos/o/r", nil, false),
        ("DELETE", "https://evil.example/notifications/threads/1", nil, false),
        ("PATCH", "https://api.github.com/notifications/threads/25131771510", nil, false),
        ("GET", "http://api.github.com/notifications", nil, false),
        ("GET", "https://github.com/notifications", nil, false),
    ] as [(String, String, String?, Bool)])
    func readOnlyGuard(method: String, url: String, body: String?, allowed: Bool) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.httpBody = body.map { Data($0.utf8) }

        #expect(GitHubClient.isAllowed(request) == allowed)
    }
}
