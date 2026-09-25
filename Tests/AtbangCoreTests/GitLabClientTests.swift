import Foundation
@testable import AtbangCore
import Testing

struct GitLabClientTests {
    private struct FakeGlab {
        let directory: URL

        var client: GitLabClient {
            GitLabClient(glab: directory.appending(path: "glab"), host: "gitlab.example.com")
        }

        var arguments: [String]? {
            (try? String(contentsOf: directory.appending(path: "args"), encoding: .utf8))?.split(separator: "\0").map(String.init)
        }

        init(stdout: String, stderr: String = "", status: Int32 = 0) throws {
            directory = FileManager.default.temporaryDirectory.appending(path: "AtbangGlab-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try stdout.write(to: directory.appending(path: "stdout"), atomically: true, encoding: .utf8)
            try stderr.write(to: directory.appending(path: "stderr"), atomically: true, encoding: .utf8)
            let glab = directory.appending(path: "glab")
            try """
            #!/bin/sh
            dir="$(dirname "$0")"
            printf '%s\\0' "$@" > "$dir/args"
            cat "$dir/stdout"
            cat "$dir/stderr" >&2
            exit \(status)
            """.write(to: glab, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: glab.path)
        }
    }

    @Test func pendingTodosBecomeNotificationsOnce() async throws {
        let commit = Fixtures.gitLabTodoJSON(id: 2, type: "Commit", url: "https://gitlab.example.com/o/r/-/commit/abc", targetUpdatedAt: "2026-09-20T10:00:00.000Z")
        let glab = try FakeGlab(stdout: [Fixtures.gitLabTodoJSON(id: 1), commit, Fixtures.gitLabTodoJSON(id: 1)].joined(separator: "\n") + "\n")

        let notifications = try await glab.client.pendingTodos()

        #expect(notifications.map(\.id) == ["gitlab:1", "gitlab:2"])
        #expect(notifications.allSatisfy { $0.forge == .gitlab })
        #expect(notifications[0].number == 7)
        #expect(notifications[0].reason == "review_requested")
        #expect(notifications[0].subject == GitHubNotification.Subject(title: "Add feature", url: URL(string: "https://gitlab.example.com/o/r/-/merge_requests/7"), type: "MergeRequest"))
        #expect(notifications[0].repository == GitHubNotification.Repository(fullName: "o/r", htmlUrl: URL(string: "https://gitlab.example.com/o/r")!))
        #expect(notifications[0].updatedAt == Fixtures.date("2026-09-22T12:00:00Z"))
        #expect(notifications[1].number == nil)
        #expect(try notifications[1].updatedAt == Date("2026-09-21T10:00:00.123Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        #expect(glab.arguments == ["api", "todos?state=pending&per_page=100", "--hostname=gitlab.example.com", "--method=GET", "--paginate", "--output=ndjson"])
    }

    @Test func gitHubNotificationsKeepTheirForge() {
        #expect(Fixtures.notification().forge == .github)
    }

    @Test func gitLabItemsLinkToTheirTargetBeforeTriage() {
        #expect(TriageItem(notification: Fixtures.gitLabNotification(), triage: nil).htmlURL.absoluteString == "https://gitlab.example.com/o/r/-/merge_requests/7")
        #expect(TriageItem(notification: Fixtures.notification(), triage: nil).htmlURL == Fixtures.notification().repository.htmlUrl)
    }

    @Test func viewerUsernameComesFromTheUserEndpoint() async throws {
        let glab = try FakeGlab(stdout: #"{"id":1,"username":"alice.smith"}"#)

        #expect(try await glab.client.viewerUsername() == "alice.smith")
        #expect(glab.arguments == ["api", "user", "--hostname=gitlab.example.com", "--method=GET"])
    }

    @Test func glabFailuresSurfaceItsExitStatus() async throws {
        let glab = try FakeGlab(stdout: "", stderr: "glab: 401 Unauthorized (HTTP 401)", status: 1)

        await #expect(throws: GitLabClient.Failure.exit(1, "glab: 401 Unauthorized (HTTP 401)")) {
            try await glab.client.viewerUsername()
        }
    }

    @Test func queriesPassTheirVariablesAsRawFields() async throws {
        struct Empty: Decodable {}
        let glab = try FakeGlab(stdout: #"{"data":{}}"#)

        _ = try await glab.client.query("query { a }", variables: ["iid": "7", "fullPath": "o/r"], as: Empty.self)

        #expect(glab.arguments == [
            "api", "graphql", "--hostname=gitlab.example.com", "--method=POST",
            "--raw-field", "fullPath=o/r", "--raw-field", "iid=7", "--raw-field", "query=query { a }",
        ])
    }

    @Test func graphQLErrorsWithoutDataThrow() async throws {
        struct Empty: Decodable {}
        let glab = try FakeGlab(stdout: #"{"data":null,"errors":[{"message":"Not found"}]}"#)

        await #expect(throws: GitLabClient.Failure.graphQL("Not found")) {
            try await glab.client.query("query { a }", variables: [:], as: Empty.self)
        }
    }

    @Test func mutationsNeverReachGlab() async throws {
        struct Empty: Decodable {}
        let glab = try FakeGlab(stdout: #"{"data":{}}"#)

        await #expect(throws: GitLabClient.Failure.notAllowed) {
            try await glab.client.query("mutation { todoMarkDone(input: {}) { errors } }", variables: [:], as: Empty.self)
        }
        #expect(glab.arguments == nil)
    }

    @Test func markAsDonePostsToTheToDo() async throws {
        let glab = try FakeGlab(stdout: "{}")

        try await glab.client.markAsDone(Fixtures.gitLabNotification())

        #expect(glab.arguments == ["api", "todos/1/mark_as_done", "--hostname=gitlab.example.com", "--method=POST"])
    }

    @Test func markAsDoneRefusesAGitHubThread() async throws {
        let glab = try FakeGlab(stdout: "{}")

        await #expect(throws: GitLabClient.Failure.notAllowed) {
            try await glab.client.markAsDone(Fixtures.notification())
        }
        #expect(glab.arguments == nil)
    }

    @Test(arguments: [
        ("user", "GET", [:], true),
        ("todos?state=pending&per_page=100", "GET", [:], true),
        ("user", "GET", ["a": "b"], false),
        ("graphql", "POST", ["query": "query { currentUser { username } }", "iid": "7"], true),
        ("graphql", "POST", ["query": "mutation { todoMarkDone(input: {}) { errors } }"], false),
        ("graphql", "POST", ["query": "query A { a } Mutation B { b }"], false),
        ("graphql", "POST", [:], false),
        ("todos/771561786/mark_as_done", "POST", [:], true),
        ("todos/1/mark_as_done", "POST", ["a": "b"], false),
        ("todos/mark_as_done", "POST", [:], false),
        ("todos/abc/mark_as_done", "POST", [:], false),
        ("todos/1/mark_as_done?x=1", "POST", [:], false),
        ("projects/1/issues", "POST", [:], false),
        ("todos/1", "DELETE", [:], false),
        ("todos/1/mark_as_done", "PUT", [:], false),
        ("https://evil.example/user", "GET", [:], false),
        ("projects/:fullpath/issues", "GET", [:], false),
    ] as [(String, String, [String: String], Bool)])
    func readOnlyGuard(endpoint: String, method: String, fields: [String: String], allowed: Bool) {
        #expect(GitLabClient.isAllowed(endpoint: endpoint, method: method, fields: fields) == allowed)
    }
}
