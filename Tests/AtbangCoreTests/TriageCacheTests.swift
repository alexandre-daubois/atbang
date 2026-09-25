import Foundation
@testable import AtbangCore
import Testing

struct TriageCacheTests {
    private let url = FileManager.default.temporaryDirectory.appending(path: "AtbangCache-\(UUID().uuidString)/cache.json")
    private let entry = TriageCache.Entry(
        key: "k",
        fingerprint: "f",
        updatedAt: Fixtures.date("2026-09-22T12:00:00Z"),
        htmlURL: URL(string: "https://github.com/o/r/pull/7")!,
        triage: Triage(priority: .medium, summary: "New comments on your PR")
    )

    @Test func roundTripsThroughDisk() throws {
        var cache = TriageCache()
        cache["1"] = entry
        try cache.save(to: url)

        #expect(TriageCache.load(from: url) == cache)
    }

    @Test func readsEntriesSavedBeforeDetailsExisted() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"{"1":{"key":"k","fingerprint":"f","updatedAt":780192000,"htmlURL":"https:\/\/github.com\/o\/r\/pull\/7","triage":{"priority":"medium","summary":"New comments on your PR"}}}"#
        try Data(json.utf8).write(to: url)

        #expect(TriageCache.load(from: url)["1"]?.details == nil)
        #expect(TriageCache.load(from: url)["1"]?.triage.priority == .medium)
    }

    @Test func startsEmptyWhenTheFileIsMissing() {
        #expect(TriageCache.load(from: url).entries.isEmpty)
    }

    @Test func startsEmptyWhenTheFileIsCorrupt() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)

        #expect(TriageCache.load(from: url).entries.isEmpty)
    }

    @Test func entryIsFreshOnlyForTheSameActivityAndPrompt() {
        let notification = Fixtures.notification()

        #expect(entry.isFresh(for: notification, fingerprint: "f"))
        #expect(!entry.isFresh(for: notification, fingerprint: "other model or prompt"))
        #expect(!entry.isFresh(for: Fixtures.notification(updatedAt: "2026-09-23T08:00:00Z"), fingerprint: "f"))
    }

    @Test func prunesThreadsThatAreNoLongerUnread() {
        var cache = TriageCache(entries: ["1": entry, "2": entry])
        cache.prune(keeping: ["2", "3"])

        #expect(cache.entries == ["2": entry])
    }
}

struct ModelsTests {
    @Test func prioritiesAreOrdered() {
        #expect(Priority.low < .medium)
        #expect(Priority.medium < .high)
        #expect(Priority.allCases.map(\.marks) == ["!", "!!", "!!!"])
    }

    @Test func numberComesFromTheSubjectURL() {
        #expect(Fixtures.notification().number == 7)
        #expect(Fixtures.notification(url: nil).number == nil)
        #expect(Fixtures.notification(url: "https://api.github.com/repos/o/r/issues/9").number == 9)
        #expect(Fixtures.notification(url: "https://api.github.com/repos/o/r/releases/123456789").number == nil)
        #expect(Fixtures.notification(url: "https://api.github.com/repos/o/r/releases/latest").number == nil)
    }
}
