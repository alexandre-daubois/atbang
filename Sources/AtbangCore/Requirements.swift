import Foundation

public struct Requirement: Sendable, Equatable, Identifiable {
    public enum Tool: String, Sendable {
        case gh, glab, claude

        public var forge: Forge? {
            switch self {
            case .gh: .github
            case .glab: .gitlab
            case .claude: nil
            }
        }
    }

    public enum Problem: Sendable, Equatable {
        case missing
        case signedOut
    }

    public let tool: Tool
    public let problem: Problem?
    public var host: String?

    public var id: String { tool.rawValue }

    public init(tool: Tool, problem: Problem?, host: String? = nil) {
        self.tool = tool
        self.problem = problem
        self.host = host
    }

    public var fix: String? {
        switch (tool, problem) {
        case (_, nil): nil
        case (.gh, .missing): "brew install gh"
        case (.gh, .signedOut): "gh auth login"
        case (.glab, .missing): "brew install glab"
        case (.glab, .signedOut): "glab auth login --hostname \(host ?? "gitlab.com")"
        case (.claude, .missing): "curl -fsSL https://claude.ai/install.sh | bash"
        case (.claude, .signedOut): "claude auth login"
        }
    }
}

public enum Requirements {
    /// GitHub and GitLab each work on their own, so only Claude or both CLIs missing hold the app back.
    public static func blocking(_ requirements: [Requirement]) -> [Requirement] {
        let missing = requirements.filter { $0.problem != nil }
        let forgeReady = requirements.contains { $0.problem == nil && $0.tool.forge != nil }
        return missing.contains { $0.tool == .claude } || !forgeReady ? missing : []
    }

    public static func check(gh: URL, glab: URL, gitLabHost: String, claude: URL) async -> [Requirement] {
        async let github = checkGitHub(gh)
        async let gitLab = checkGitLab(glab, host: gitLabHost)
        async let claudeCode = checkClaude(claude)
        return await [github, gitLab, claudeCode]
    }

    static func checkGitHub(_ gh: URL) async -> Requirement {
        guard FileManager.default.isExecutableFile(atPath: gh.path) else { return Requirement(tool: .gh, problem: .missing) }
        let signedIn = (try? await GitHubClient.token(gh: gh)) != nil
        return Requirement(tool: .gh, problem: signedIn ? nil : .signedOut)
    }

    static func checkGitLab(_ glab: URL, host: String) async -> Requirement {
        guard FileManager.default.isExecutableFile(atPath: glab.path) else { return Requirement(tool: .glab, problem: .missing, host: host) }
        let output = try? await ProcessRunner.run(glab, arguments: ["auth", "status", "--hostname=\(host)"], timeout: .seconds(20))
        return Requirement(tool: .glab, problem: output?.status == 0 ? nil : .signedOut, host: host)
    }

    static func checkClaude(_ claude: URL) async -> Requirement {
        struct Status: Decodable { let loggedIn: Bool }
        guard FileManager.default.isExecutableFile(atPath: claude.path) else { return Requirement(tool: .claude, problem: .missing) }
        let output = try? await ProcessRunner.run(claude, arguments: ["auth", "status", "--json"], timeout: .seconds(20))
        let signedIn = output.flatMap { try? JSONDecoder().decode(Status.self, from: $0.stdout) }?.loggedIn == true
        return Requirement(tool: .claude, problem: signedIn ? nil : .signedOut)
    }
}
