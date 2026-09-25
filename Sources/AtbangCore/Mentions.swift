import Foundation

public enum Mentions {
    // A login is alphanumeric with inner hyphens, plus dots and underscores on GitLab, bots end with `[bot]`, a team or a GitLab subgroup adds `/slug`, and a preceding letter means an email address.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9@])@[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9_])?(?:\[bot\]|(?:/[A-Za-z0-9_.-]*[A-Za-z0-9_])+)?"#
    )

    public static func ranges(in text: String) -> [Range<String.Index>] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }
}
