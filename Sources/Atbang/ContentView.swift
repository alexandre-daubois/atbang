import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showsSettings = false
    // Kept here so switching pages reuses the measured sizes instead of resizing the window twice.
    @State private var rowBottoms: [String: CGFloat] = [:]
    @State private var settingsHeight: CGFloat = 470

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model, showsSettings: $showsSettings)
            Divider()
            if showsSettings {
                SettingsView(model: model, contentHeight: $settingsHeight)
            } else if !model.missingRequirements.isEmpty {
                SetupView(model: model)
            } else {
                NotificationList(model: model, rowBottoms: $rowBottoms)
            }
        }
        .frame(width: 420)
        .onDisappear { model.collapseDetails() }
    }
}

private struct Header: View {
    @Bindable var model: AppModel
    @Binding var showsSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(showsSettings ? "Settings" : model.missingRequirements.isEmpty ? "Notifications" : "Finish Setting Up")
                    .font(.system(size: 13, weight: .semibold))
                if !showsSettings, model.missingRequirements.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: subtitle)
                }
            }
            Spacer()
            if showsSettings {
                Button("Done") { showsSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            } else {
                Group {
                    groupByRepository
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { model.missingRequirements.isEmpty ? await model.refresh() : await model.checkRequirements() }
                    }
                    .symbolEffect(.rotate, isActive: model.isRefreshing || model.isCheckingRequirements)
                    .disabled(model.isRefreshing || model.isCheckingRequirements)
                        .help("Refresh")
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                        .help("Settings")
                    Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                        .help("Quit Atbang")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 52)
    }

    @ViewBuilder private var groupByRepository: some View {
        let toggle = Toggle("Group by Repository", systemImage: "book.closed", isOn: $model.groupsByRepository)
            .toggleStyle(.button)
            .help("Group by repository")
        if model.groupsByRepository {
            toggle
                .foregroundStyle(.white)
                .background(Color.accentColor, in: .circle)
        } else {
            toggle
        }
    }

    private var subtitle: String {
        if model.isRefreshing {
            let done = model.items.count - model.pendingCount
            return model.pendingCount > 0 ? "Triaging \(done) of \(model.items.count)…" : "Checking GitHub…"
        }
        guard let lastRefresh = model.lastRefresh else { return "Not checked yet" }
        let unread = model.items.count == 1 ? "1 unread" : "\(model.items.count) unread"
        return "\(unread) · Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))"
    }
}
