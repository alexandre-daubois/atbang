import AppKit
import AtbangCore
import SwiftUI

struct SetupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atbang reads your notifications with the GitHub CLI, the GitLab CLI or both, and triages them with \(model.harness.name). Run the commands below in Terminal, then check again.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(model.requirements) { requirement in
                    RequirementRow(requirement: requirement)
                    if requirement.id != model.requirements.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(.quinary, in: .rect(corners: .concentric(minimum: 12), isUniform: true))
            HStack {
                Text("Installed somewhere else? Set the path in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Check Again") { Task { await model.checkRequirements() } }
                    .buttonStyle(.glassProminent)
                    .disabled(model.isCheckingRequirements)
            }
        }
        .padding(16)
    }
}

private struct RequirementRow: View {
    let requirement: Requirement

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let fix = requirement.fix {
                    HStack(spacing: 6) {
                        Text(fix)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fix, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Copy the command")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: .rect(corners: .concentric(minimum: 8), isUniform: true))
                }
            }
        }
        .padding(12)
    }

    private var name: String {
        switch requirement.tool {
        case .gh: "GitHub CLI"
        case .glab: "GitLab CLI"
        case .claude: "Claude Code"
        case .appleIntelligence: "Apple Intelligence"
        }
    }

    private var symbol: String {
        switch requirement.problem {
        case nil: "checkmark.circle.fill"
        case .missing, .unsupported: "xmark.circle.fill"
        case .signedOut, .turnedOff, .downloading: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch requirement.problem {
        case nil: .green
        case .missing, .unsupported: .red
        case .signedOut, .turnedOff, .downloading: .orange
        }
    }

    private var status: String {
        switch requirement.problem {
        case nil: "Ready"
        case .missing: "Not installed"
        case .signedOut: "Signed out"
        case .unsupported: "Not supported on this Mac"
        case .turnedOff: "Turned off"
        case .downloading: "Downloading"
        }
    }
}
