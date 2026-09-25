import Foundation
@testable import AtbangCore
import Testing

struct RequirementsTests {
    private func executable(_ source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AtbangRequirements-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "tool")
        try "#!/bin/sh\n\(source)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func allToolsReady() async throws {
        let gh = try executable("echo gho_token")
        let glab = try executable("exit 0")
        let claude = try executable(#"echo '{"loggedIn": true, "authMethod": "claude.ai"}'"#)

        let requirements = await Requirements.check(gh: gh, glab: glab, gitLabHost: "gitlab.com", claude: claude)

        #expect(requirements == [Requirement(tool: .gh, problem: nil), Requirement(tool: .glab, problem: nil, host: "gitlab.com"), Requirement(tool: .claude, problem: nil)])
        #expect(requirements.allSatisfy { $0.fix == nil })
    }

    @Test func missingTools() async {
        let requirements = await Requirements.check(
            gh: URL(filePath: "/nonexistent/gh"),
            glab: URL(filePath: "/nonexistent/glab"),
            gitLabHost: "gitlab.com",
            claude: URL(filePath: "/nonexistent/claude")
        )

        #expect(requirements.map(\.problem) == [.missing, .missing, .missing])
        #expect(requirements.map(\.fix) == ["brew install gh", "brew install glab", "curl -fsSL https://claude.ai/install.sh | bash"])
    }

    @Test(arguments: [
        ([Requirement.Problem?.none, .missing, nil], [Requirement.Tool]()),
        ([.signedOut, nil, nil], []),
        ([nil, nil, nil], []),
        ([.missing, .signedOut, nil], [.gh, .glab]),
        ([nil, .missing, .signedOut], [.glab, .claude]),
    ])
    func eitherForgeIsEnough(problems: [Requirement.Problem?], blocking: [Requirement.Tool]) {
        let requirements = zip([Requirement.Tool.gh, .glab, .claude], problems).map { Requirement(tool: $0, problem: $1) }

        #expect(Requirements.blocking(requirements).map(\.tool) == blocking)
    }

    @Test func nothingBlocksBeforeTheFirstCheck() {
        #expect(Requirements.blocking([]).isEmpty)
    }

    @Test func signedOutGitLabPointsAtTheHost() async throws {
        let requirement = await Requirements.checkGitLab(try executable("echo 'has not been authenticated' >&2; exit 1"), host: "gitlab.example.com")

        #expect(requirement.problem == .signedOut)
        #expect(requirement.fix == "glab auth login --hostname gitlab.example.com")
    }

    @Test func glabIsAskedForTheHostsAuthStatusOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AtbangRequirements-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let glab = directory.appending(path: "glab")
        try "#!/bin/sh\necho \"$@\" > \"$(dirname \"$0\")/args\"\n".write(to: glab, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: glab.path)

        _ = await Requirements.checkGitLab(glab, host: "gitlab.example.com")

        #expect(try String(contentsOf: directory.appending(path: "args"), encoding: .utf8) == "auth status --hostname=gitlab.example.com\n")
    }

    @Test func signedOutGitHub() async throws {
        let requirement = await Requirements.checkGitHub(try executable("echo 'no oauth token found' >&2; exit 1"))

        #expect(requirement == Requirement(tool: .gh, problem: .signedOut))
        #expect(requirement.fix == "gh auth login")
    }

    @Test(arguments: [
        #"echo '{"loggedIn": false}'"#,
        "echo 'not json'",
        "exit 1",
    ])
    func signedOutClaude(script: String) async throws {
        let requirement = await Requirements.checkClaude(try executable(script))

        #expect(requirement == Requirement(tool: .claude, problem: .signedOut))
        #expect(requirement.fix == "claude auth login")
    }

    @Test func claudeIsAskedForItsAuthStatusOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AtbangRequirements-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let claude = directory.appending(path: "claude")
        try "#!/bin/sh\necho \"$@\" > \"$(dirname \"$0\")/args\"\necho '{\"loggedIn\": true}'\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        _ = await Requirements.checkClaude(claude)

        #expect(try String(contentsOf: directory.appending(path: "args"), encoding: .utf8) == "auth status --json\n")
    }
}
