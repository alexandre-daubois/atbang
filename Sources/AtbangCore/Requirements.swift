import Foundation

public struct Requirement: Sendable, Equatable, Identifiable {
    public enum Tool: String, Sendable {
        case gh, claude
    }

    public enum Problem: Sendable, Equatable {
        case missing
        case signedOut
    }

    public let tool: Tool
    public let problem: Problem?

    public var id: String { tool.rawValue }

    public init(tool: Tool, problem: Problem?) {
        self.tool = tool
        self.problem = problem
    }

    /// The command that fixes the problem, as documented by GitHub and Anthropic.
    public var fix: String? {
        switch (tool, problem) {
        case (_, nil): nil
        case (.gh, .missing): "brew install gh"
        case (.gh, .signedOut): "gh auth login"
        case (.claude, .missing): "curl -fsSL https://claude.ai/install.sh | bash"
        case (.claude, .signedOut): "claude auth login"
        }
    }
}

/// Checks that both command-line tools are installed and signed in, without any inference or network write.
public enum Requirements {
    public static func check(gh: URL, claude: URL) async -> [Requirement] {
        async let github = checkGitHub(gh)
        async let claudeCode = checkClaude(claude)
        return await [github, claudeCode]
    }

    static func checkGitHub(_ gh: URL) async -> Requirement {
        guard FileManager.default.isExecutableFile(atPath: gh.path) else { return Requirement(tool: .gh, problem: .missing) }
        let signedIn = (try? await GitHubClient.token(gh: gh)) != nil
        return Requirement(tool: .gh, problem: signedIn ? nil : .signedOut)
    }

    static func checkClaude(_ claude: URL) async -> Requirement {
        struct Status: Decodable { let loggedIn: Bool }
        guard FileManager.default.isExecutableFile(atPath: claude.path) else { return Requirement(tool: .claude, problem: .missing) }
        let output = try? await ProcessRunner.run(claude, arguments: ["auth", "status", "--json"], timeout: .seconds(20))
        let signedIn = output.flatMap { try? JSONDecoder().decode(Status.self, from: $0.stdout) }?.loggedIn == true
        return Requirement(tool: .claude, problem: signedIn ? nil : .signedOut)
    }
}
