import AppKit
import AtbangCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var contentHeight: CGFloat

    var body: some View {
        Form {
            Section("General") {
                Picker("Check for notifications", selection: $model.refreshMinutes) {
                    ForEach(AppModel.refreshChoices, id: \.self) { Text(Self.label(minutes: $0)).tag($0) }
                }
                Toggle("Show the notification count in the menu bar", isOn: $model.showsMenuBarCount)
            }
            Section {
                Picker("Triage with", selection: $model.harness) {
                    ForEach(Harness.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                if model.harness == .claudeCode {
                    Picker("Model", selection: $model.claudeModel) {
                        ForEach(AppModel.claudeModels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    ExecutableField(path: $model.claudePath)
                }
            } header: {
                Text("Triage")
            } footer: {
                switch model.harness {
                case .claudeCode:
                    SettingsFooter("Each alias follows the latest version of its model. A thread only goes back to Claude when it changes, or when the model does.")
                case .appleIntelligence:
                    SettingsFooter("Apple’s on-device model runs on this Mac, so threads never leave it. A thread only goes back to the model when it changes.")
                }
            }
            Section {
                ExecutableField(path: $model.ghPath)
            } header: {
                Text("GitHub")
            } footer: {
                SettingsFooter("Notifications and threads are only read. The one write is Mark as Done, on the notification you pick.")
            }
            Section {
                LabeledContent("Host") {
                    TextField("Host", text: $model.gitLabHost)
                        .labelsHidden()
                        .font(.system(size: 12, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .onSubmit { Task { await model.checkRequirements() } }
                }
                ExecutableField(path: $model.glabPath)
            } header: {
                Text("GitLab")
            } footer: {
                SettingsFooter("To-do items and threads are only read, through glab. The one write is Mark as Done, on the to-do item you pick.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { contentHeight = $1 }
        // The menu bar window only sizes a scrolling Form from an explicit height.
        .frame(height: contentHeight)
    }

    private static func label(minutes: Int) -> String {
        switch minutes {
        case 1: "Every minute"
        case 60: "Every hour"
        default: "Every \(minutes) minutes"
        }
    }
}

private struct ExecutableField: View {
    @Binding var path: String

    var body: some View {
        LabeledContent("Executable") {
            HStack(spacing: 6) {
                TextField("Executable", text: $path)
                    .labelsHidden()
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                Image(systemName: isExecutable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isExecutable ? .green : .red)
                    .help(isExecutable ? "Found" : "No executable at this path")
            }
        }
    }

    private var isExecutable: Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

private struct SettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
