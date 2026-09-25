import AppKit
import AtbangCore
import SwiftUI

struct NotificationList: View {
    private static let visibleRows = 4
    nonisolated private static let space = "notifications"

    let model: AppModel
    @Binding var rowBottoms: [String: CGFloat]

    var body: some View {
        if model.items.isEmpty {
            placeholder.frame(height: 220)
        } else {
            VStack(spacing: 0) {
                if let error = model.error {
                    ErrorBanner(message: error)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.key) { section in
                            SectionHeader(key: section.key, count: section.items.count)
                            ForEach(section.items) { item in
                                NotificationRow(
                                    item: item,
                                    showsRepository: !model.groupsByRepository,
                                    open: { model.open(item) },
                                    markAsDone: { Task { await model.markAsDone(item) } },
                                    isExpanded: model.expandedIDs.contains(item.id),
                                    showDetails: { Task { await model.showDetails(item) } }
                                )
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: {
                                        rowBottoms[item.id] = $0
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                    .coordinateSpace(.named(Self.space))
                    .animation(.snappy, value: model.items.map(\.id))
                    .animation(.snappy, value: model.groupsByRepository)
                }
                // A ScrollView has no ideal height: without an explicit one the menu bar window collapses it.
                .frame(height: listHeight)
            }
        }
    }

    private var listHeight: CGFloat {
        let visible = sections.flatMap(\.items).prefix(Self.visibleRows)
        return (visible.compactMap { rowBottoms[$0.id] }.max() ?? CGFloat(visible.count) * 80) + 6
    }

    /// Items are already sorted by priority, so either grouping keeps the most urgent sections and rows first.
    private var sections: [(key: SectionKey, items: [TriageItem])] {
        var sections: [(key: SectionKey, items: [TriageItem])] = []
        for item in model.items {
            let key: SectionKey = model.groupsByRepository ? .repository(item.notification.repository.fullName) : .priority(item.triage?.priority)
            if let index = sections.firstIndex(where: { $0.key == key }) {
                sections[index].items.append(item)
            } else {
                sections.append((key, [item]))
            }
        }
        return sections
    }

    @ViewBuilder private var placeholder: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label("Can’t Reach GitHub", systemImage: "exclamationmark.icloud")
            } description: {
                Text(error).lineLimit(4)
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
            }
        } else if model.lastRefresh == nil {
            ProgressView().controlSize(.small)
        } else {
            ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unread notifications."))
        }
    }
}

private enum SectionKey: Hashable {
    case priority(Priority?)
    case repository(String)
}

private struct SectionHeader: View {
    let key: SectionKey
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(String(count))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        switch key {
        case .priority(.high): "Waiting on You"
        case .priority(.medium): "Worth a Look"
        case .priority(.low): "For Your Information"
        case .priority(nil): "Not Triaged Yet"
        case let .repository(name): name
        }
    }
}

struct NotificationRow: View {
    let item: TriageItem
    let showsRepository: Bool
    let open: () -> Void
    let markAsDone: () -> Void
    let isExpanded: Bool
    let showDetails: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PriorityBadge(priority: item.triage?.priority, isPending: item.status == .pending)
            VStack(alignment: .leading, spacing: 3) {
                metadata
                Text(item.notification.subject.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if let summary = item.triage?.summary {
                    Text(summaryText(summary))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(expandedDetails == nil ? 3 : nil)
                        .shimmering(item.details == .loading)
                        .environment(\.openURL, OpenURLAction { _ in
                            showDetails()
                            return .handled
                        })
                        .help(failure ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(hovered ? 0.8 : 0), in: .rect(corners: .concentric(minimum: 10), isUniform: true))
        .contentShape(.rect(corners: .concentric(minimum: 10), isUniform: true))
        // A tap rather than a Button, so the "More…" link inside the summary keeps its own click.
        .onTapGesture(perform: open)
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button("Mark as Done", systemImage: "checkmark", action: markAsDone)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Mark as Done")
                    .padding(.top, 4)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 6)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Open in Browser", action: open)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.htmlURL.absoluteString, forType: .string)
            }
            Divider()
            Button("Mark as Done", action: markAsDone)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private var expandedDetails: String? {
        guard isExpanded, case let .loaded(details) = item.details else { return nil }
        return details
    }

    private var failure: String? {
        if case let .failed(message) = item.details { message } else { nil }
    }

    private static let moreURL = URL(string: "atbang:more")!

    /// The link keeps its place while hidden, so hovering never reflows the text, and a no-break space ties it to
    /// the last word so it never wraps onto a line of its own.
    private func summaryText(_ summary: String) -> AttributedString {
        if let expandedDetails { return Self.emphasizingMentions(in: expandedDetails) }
        var text = Self.emphasizingMentions(in: summary)
        if item.details == .loading {
            text.append(AttributedString("\u{00A0}Loading…"))
            return text
        }
        var link = AttributedString(failure == nil ? "\u{00A0}More…" : "\u{00A0}Try\u{00A0}again")
        link.link = Self.moreURL
        if !hovered { link.foregroundColor = .clear }
        text.append(link)
        return text
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if showsRepository {
                Text(item.notification.repository.fullName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            if let number = item.notification.number {
                Text(verbatim: "#\(number)").monospacedDigit()
            }
            if showsRepository || item.notification.number != nil {
                Text("·")
            }
            Text(reason).lineLimit(1)
            if case let .failed(message) = item.status {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
            }
            Spacer(minLength: 6)
            Text(age)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .help(item.notification.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .opacity(hovered ? 0 : 1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private static func emphasizingMentions(in summary: String) -> AttributedString {
        var text = AttributedString(summary)
        for range in Mentions.ranges(in: summary) {
            guard let range = Range(range, in: text) else { continue }
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    private var symbol: String {
        switch item.notification.subject.type {
        case "PullRequest": "arrow.triangle.pull"
        case "Issue": "smallcircle.filled.circle"
        case "RepositoryAdvisory": "shield.lefthalf.filled"
        case "Release": "tag"
        case "Discussion": "bubble.left.and.bubble.right"
        case "CheckSuite", "WorkflowRun": "checkmark.circle"
        case "Commit": "point.3.connected.trianglepath.dotted"
        default: "bell"
        }
    }

    private var reason: String {
        switch item.notification.reason {
        case "assign": "Assigned"
        case "mention": "Mentioned"
        case "team_mention": "Team mentioned"
        case "state_change": "State changed"
        case "ci_activity": "CI activity"
        case "manual": "Subscribed"
        case "security_advisory_credit": "Credited"
        case let reason:
            reason.prefix(1).uppercased() + reason.dropFirst().replacingOccurrences(of: "_", with: " ")
        }
    }

    private var age: String {
        let seconds = max(0, Date.now.timeIntervalSince(item.notification.updatedAt))
        return switch seconds {
        case ..<60: "now"
        case ..<3600: "\(Int(seconds / 60))m"
        case ..<86400: "\(Int(seconds / 3600))h"
        case ..<604_800: "\(Int(seconds / 86400))d"
        default: "\(Int(seconds / 604_800))w"
        }
    }
}

private struct PriorityBadge: View {
    let priority: Priority?
    let isPending: Bool

    var body: some View {
        ZStack {
            if let priority {
                Text(priority.marks)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
            } else if isPending {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 20)
        .background(tint.opacity(0.15), in: Capsule())
        .accessibilityLabel(priority.map { "Priority \($0.rawValue)" } ?? "Not triaged")
    }

    private var tint: Color {
        switch priority {
        case .high: .red
        case .medium: .orange
        case .low, nil: .secondary
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message).lineLimit(2)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.orange.opacity(0.12), in: .rect(corners: .concentric(minimum: 10), isUniform: true))
        .padding([.horizontal, .top], 10)
        .help(message)
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .mask {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .black, .black.opacity(0.35)],
                        startPoint: UnitPoint(x: phase - 0.5, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.5, y: 0.5)
                    )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.5 }
                }
        }
    }
}

private extension View {
    @ViewBuilder func shimmering(_ active: Bool) -> some View {
        if active { modifier(Shimmer()) } else { self }
    }
}
