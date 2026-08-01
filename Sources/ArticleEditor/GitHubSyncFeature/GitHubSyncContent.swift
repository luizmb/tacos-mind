import AppDomain
import SwiftUI

public struct GitHubSyncContent: View {
    @Environment(\.dismiss) private var dismiss

    let isConfigured: Bool
    let repoURLInput: Binding<String>
    let branchInput: Binding<String>
    let tokenInput: Binding<String>
    let isSavingSettings: Bool
    let isPulling: Bool
    let pendingPullPreview: PullPreview?
    let isCommitting: Bool
    let lastCommitOutcome: CommitOutcome?
    let isOpeningPR: Bool
    let lastPRURL: URL?
    let lastError: String?
    let isConfirmingPull: Binding<Bool>
    let onSaveSettings: () -> Void
    let onPull: () -> Void
    let onConfirmPull: () -> Void
    let onCommit: () -> Void
    let onOpenPR: () -> Void

    public var body: some View {
        NavigationStack {
            Form {
                settingsSection
                actionsSection
                if let lastError {
                    Section {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("GitHub Sync")
            .toolbar {
                // macOS sheets get no close affordance for free — without this the sheet
                // (confirmed via screenshot) has no way to dismiss at all.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "This will overwrite local changes",
                isPresented: isConfirmingPull,
                titleVisibility: .visible
            ) {
                Button("Pull and Overwrite", role: .destructive, action: onConfirmPull)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let pendingPullPreview {
                    Text(
                        "\(pendingPullPreview.localOnlyChanges.count) article(s) have local changes not on GitHub: " +
                        "\(pendingPullPreview.localOnlyChanges.joined(separator: ", ")). Pulling will overwrite them."
                    )
                }
            }
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            TextField("Repo URL", text: repoURLInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("Branch", text: branchInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            // The field is never pre-filled with the stored secret (see
            // `GitHubSyncFeature.settingsLoaded`) — once a token is saved, leaving this
            // blank on the next Save keeps it unchanged; only typing a new value rotates it.
            SecureField(isConfigured ? "Leave blank to keep the current token" : "Personal Access Token", text: tokenInput)
            if isConfigured {
                Text("A token is already saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                onSaveSettings()
            } label: {
                if isSavingSettings {
                    ProgressView()
                } else {
                    Text("Save")
                }
            }
            .disabled(isSavingSettings)
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            actionRow(
                title: "Pull from GitHub",
                systemImage: "arrow.down.circle",
                isBusy: isPulling,
                disabled: !isConfigured || isPulling,
                action: onPull
            )
            actionRow(
                title: "Commit local changes",
                systemImage: "arrow.up.circle",
                isBusy: isCommitting,
                disabled: !isConfigured || isCommitting,
                action: onCommit
            )
            if let lastCommitOutcome {
                commitOutcomeView(lastCommitOutcome)
            }
            actionRow(
                title: "Open Pull Request",
                systemImage: "arrow.triangle.pull",
                isBusy: isOpeningPR,
                disabled: !isConfigured || isOpeningPR,
                action: onOpenPR
            )
            if let lastPRURL {
                Link("View Pull Request", destination: lastPRURL)
            }
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        isBusy: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isBusy {
                    ProgressView()
                }
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private func commitOutcomeView(_ outcome: CommitOutcome) -> some View {
        switch outcome {
        case .nothingToCommit:
            Text("Nothing to commit — everything's already on GitHub.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .committed(let files, let commitURL):
            VStack(alignment: .leading, spacing: 4) {
                Text("Committed \(files.count) file(s): \(files.joined(separator: ", "))")
                    .font(.footnote)
                Link("View Commit", destination: commitURL)
            }
        }
    }
}
