import Foundation
@testable import AtbangCore
import Testing

struct MentionsTests {
    @Test(arguments: [
        ("@bob asks you whether the fix covers 8.3", ["@bob"]),
        ("Your PR: changes requested by @dave.", ["@dave"]),
        ("Review requested from @php/frankenphp-maintainers, not you", ["@php/frankenphp-maintainers"]),
        ("@henderkes and @dunglas discuss, @withinboredom approved", ["@henderkes", "@dunglas", "@withinboredom"]),
        ("@dependabot-preview's bump", ["@dependabot-preview"]),
        ("@dependabot[bot] bumps swift-nio, @github-actions[bot] failed", ["@dependabot[bot]", "@github-actions[bot]"]),
        ("@bob[bots] and @bob[", ["@bob", "@bob"]),
        ("Closed PR, nothing needs you", []),
        ("Reported by bob@example.com", []),
        ("Trailing @ sign and @-dash", []),
        ("@alexandre.daubois and @jane_doe reviewed.", ["@alexandre.daubois", "@jane_doe"]),
        ("Ask @gitlab-org/cli/maintainers.", ["@gitlab-org/cli/maintainers"]),
    ])
    func findsMentions(text: String, expected: [String]) {
        #expect(Mentions.ranges(in: text).map { String(text[$0]) } == expected)
    }
}
