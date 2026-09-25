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

    @Test func bothToolsReady() async throws {
        let gh = try executable("echo gho_token")
        let claude = try executable(#"echo '{"loggedIn": true, "authMethod": "claude.ai"}'"#)

        let requirements = await Requirements.check(gh: gh, claude: claude)

        #expect(requirements == [Requirement(tool: .gh, problem: nil), Requirement(tool: .claude, problem: nil)])
        #expect(requirements.allSatisfy { $0.fix == nil })
    }

    @Test func missingTools() async {
        let requirements = await Requirements.check(gh: URL(filePath: "/nonexistent/gh"), claude: URL(filePath: "/nonexistent/claude"))

        #expect(requirements.map(\.problem) == [.missing, .missing])
        #expect(requirements.map(\.fix) == ["brew install gh", "curl -fsSL https://claude.ai/install.sh | bash"])
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
