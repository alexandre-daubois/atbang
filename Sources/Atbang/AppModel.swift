import AppKit
import AtbangCore
import Observation

@MainActor
@Observable
final class AppModel {
    static let refreshChoices = [1, 2, 5, 10, 15, 30, 60]
    static let claudeModels = ["haiku", "sonnet", "opus", "fable"]
    private static let maxConcurrentTriages = 3

    private(set) var items: [TriageItem] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var error: String?
    /// Rows showing their longer explanation. Not persisted, and reset whenever the popover closes.
    private(set) var expandedIDs: Set<String> = []
    private(set) var requirements: [Requirement] = []
    private(set) var isCheckingRequirements = false

    var refreshMinutes = UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 5 {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes")
            if timer != nil { scheduleRefreshes() }
        }
    }

    var groupsByRepository = UserDefaults.standard.bool(forKey: "groupsByRepository") {
        didSet { UserDefaults.standard.set(groupsByRepository, forKey: "groupsByRepository") }
    }

    var showsMenuBarCount = UserDefaults.standard.object(forKey: "showsMenuBarCount") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsMenuBarCount, forKey: "showsMenuBarCount") }
    }

    var claudeModel = UserDefaults.standard.string(forKey: "claudeModel").flatMap { claudeModels.contains($0) ? $0 : nil } ?? "sonnet" {
        didSet {
            UserDefaults.standard.set(claudeModel, forKey: "claudeModel")
            // A 304 would skip the per-thread checks that notice the new model.
            etag = nil
        }
    }

    var ghPath = UserDefaults.standard.string(forKey: "ghPath") ?? Executable.locate("gh") ?? "/opt/homebrew/bin/gh" {
        didSet { UserDefaults.standard.set(ghPath, forKey: "ghPath") }
    }

    var claudePath = UserDefaults.standard.string(forKey: "claudePath") ?? Executable.locate("claude") ?? "claude" {
        didSet { UserDefaults.standard.set(claudePath, forKey: "claudePath") }
    }

    @ObservationIgnored private var cache = TriageCache.load(from: TriageCache.defaultURL)
    @ObservationIgnored private var timer: Task<Void, Never>?
    // GitHub can still list a thread right after it was marked done, until its next activity.
    @ObservationIgnored private var markedDone: [String: Date] = [:]
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var pollInterval = 60

    var highPriorityCount: Int {
        items.filter { $0.triage?.priority == .high }.count
    }

    var pendingCount: Int {
        items.filter { $0.status == .pending }.count
    }

    var missingRequirements: [Requirement] {
        requirements.filter { $0.problem != nil }
    }

    init() {
        Task { await checkRequirements() }
    }

    /// Refreshes only start once both tools are installed and signed in.
    func checkRequirements() async {
        guard !isCheckingRequirements else { return }
        isCheckingRequirements = true
        defer { isCheckingRequirements = false }
        // A tool installed while the app runs is picked up without a trip to Settings.
        if !FileManager.default.isExecutableFile(atPath: ghPath), let found = Executable.locate("gh") { ghPath = found }
        if !FileManager.default.isExecutableFile(atPath: claudePath), let found = Executable.locate("claude") { claudePath = found }
        requirements = await Requirements.check(gh: URL(filePath: ghPath), claude: URL(filePath: claudePath))
        if missingRequirements.isEmpty, timer == nil { scheduleRefreshes() }
    }

    func collapseDetails() {
        expandedIDs.removeAll()
    }

    func open(_ item: TriageItem) {
        guard item.htmlURL.scheme == "https", item.htmlURL.host() == "github.com" else { return }
        NSWorkspace.shared.open(item.htmlURL)
    }

    func markAsDone(_ item: TriageItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        markedDone[removed.id] = removed.notification.updatedAt
        do {
            let client = GitHubClient(token: try await GitHubClient.token(gh: URL(filePath: ghPath)))
            try await client.markAsDone(threadID: removed.id)
            cache[removed.id] = nil
            try? cache.save(to: TriageCache.defaultURL)
        } catch {
            markedDone[removed.id] = nil
            if !items.contains(where: { $0.id == removed.id }) {
                items.append(removed)
                sortItems()
            }
            self.error = "Mark as Done failed: \(error)"
        }
    }

    /// An explanation cached for the current state of the thread expands at once, without GitHub nor Claude.
    func showDetails(_ item: TriageItem) async {
        if case .loaded = item.details {
            expandedIDs.insert(item.id)
            return
        }
        await loadDetails(item)
        if case .loaded = items.first(where: { $0.id == item.id })?.details {
            expandedIDs.insert(item.id)
        }
    }

    private func loadDetails(_ item: TriageItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index].details != .loading else { return }
        items[index].details = .loading
        let details: TriageItem.Details
        do {
            let client = GitHubClient(token: try await GitHubClient.token(gh: URL(filePath: ghPath)))
            let context = try await GitHubContextProvider(client: client, viewer: try await client.viewerLogin()).context(for: item.notification)
            let input = TriagePrompt.input(for: context)
            let explanation = try await ClaudeClassifier(executable: URL(filePath: claudePath), model: claudeModel).explain(input)
            if cache[item.id]?.key == TriagePrompt.cacheKey(model: claudeModel, input: input) {
                cache[item.id]?.details = explanation
                try? cache.save(to: TriageCache.defaultURL)
            }
            details = .loaded(explanation)
        } catch {
            details = .failed(String(describing: error))
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].details = details
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let notifications: [GitHubNotification]
        let unread: GitHubClient.UnreadNotifications
        let triager: Triager
        do {
            let client = GitHubClient(token: try await GitHubClient.token(gh: URL(filePath: ghPath)))
            // A thread left pending or failed needs another pass even when the list itself did not change.
            unread = try await client.unreadNotifications(ifNoneMatch: items.allSatisfy { $0.status == .done } ? etag : nil)
            pollInterval = unread.pollInterval ?? pollInterval
            guard let fetched = unread.notifications else {
                error = nil
                lastRefresh = .now
                return
            }
            triager = Triager(
                contexts: GitHubContextProvider(client: client, viewer: try await client.viewerLogin()),
                classifier: ClaudeClassifier(executable: URL(filePath: claudePath), model: claudeModel)
            )
            // After the last await, so a thread marked done while this refresh waited stays gone.
            notifications = fetched.filter { notification in
                markedDone[notification.id].map { notification.updatedAt > $0 } ?? true
            }
            error = nil
        } catch {
            self.error = String(describing: error)
            return
        }

        let fingerprint = triager.fingerprint
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = notifications.map {
            var item = TriageItem(notification: $0, triage: cache[$0.id]?.triage)
            if let htmlURL = cache[$0.id]?.htmlURL ?? previous[$0.id]?.htmlURL { item.htmlURL = htmlURL }
            if cache[$0.id]?.isFresh(for: $0, fingerprint: fingerprint) == true { item.status = .done }
            item.details = cache[$0.id]?.details.map { .loaded($0) } ?? previous[$0.id]?.details
            return item
        }
        sortItems()

        let cache = cache
        let stale = notifications.filter { cache[$0.id]?.isFresh(for: $0, fingerprint: fingerprint) != true }
        await withTaskGroup(of: TriageResult.self) { group in
            var queue = stale.makeIterator()
            for _ in 0..<Self.maxConcurrentTriages {
                guard let notification = queue.next() else { break }
                group.addTask { await triager.triage(notification, cached: cache[notification.id]) }
            }
            for await result in group {
                apply(result)
                if let notification = queue.next() {
                    group.addTask { await triager.triage(notification, cached: cache[notification.id]) }
                }
            }
        }

        self.cache.prune(keeping: Set(notifications.map(\.id)))
        try? self.cache.save(to: TriageCache.defaultURL)
        if triager.fingerprint == TriagePrompt.fingerprint(model: claudeModel) { etag = unread.etag }
        lastRefresh = .now
    }

    private func apply(_ result: TriageResult) {
        guard let index = items.firstIndex(where: { $0.id == result.threadID }) else { return }
        if let htmlURL = result.htmlURL { items[index].htmlURL = htmlURL }
        if let entry = result.entry {
            cache[result.threadID] = entry
            items[index].triage = entry.triage
            if items[index].details != .loading { items[index].details = entry.details.map { .loaded($0) } }
        }
        items[index].status = result.failure.map { .failed($0) } ?? .done
        sortItems()
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            switch (lhs.triage?.priority, rhs.triage?.priority) {
            case let (left?, right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.notification.updatedAt > rhs.notification.updatedAt
            }
        }
    }

    private func scheduleRefreshes() {
        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                Task { await refresh() }
                // GitHub asks clients not to poll notifications more often than X-Poll-Interval.
                try? await Task.sleep(for: .seconds(max(refreshMinutes * 60, pollInterval)))
            }
        }
    }
}
