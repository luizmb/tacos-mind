import AppDomain
import SwiftUI

public struct GitHubSyncContent: View {
    let path: Binding<[GitHubSyncRoute]>
    let isConfigured: Bool
    let repoURL: String
    let branch: String
    let isPulling: Bool
    let pendingPullPreview: PullPreview?
    let isCommitting: Bool
    let lastCommitOutcome: CommitOutcome?
    let isOpeningPR: Bool
    let lastPRURL: URL?
    let lastError: String?
    let isConfirmingPull: Binding<Bool>
    let onDone: () -> Void
    let onRequestLink: () -> Void
    let onRequestUnlink: () -> Void
    let onRequestEditBranch: () -> Void
    let onPull: () -> Void
    let onConfirmPull: () -> Void
    let onCommit: () -> Void
    let onOpenPR: () -> Void

    let isConfirmingUnlink: Binding<Bool>
    let isUnlinking: Bool
    let onConfirmUnlink: () -> Void

    let linkScreen: LinkRepositoryContent
    let editBranchScreen: EditBranchContent

    /// Link and Edit Branch are **pushed**, not sheeted. Two sheets and two confirmation
    /// dialogs presented from inside a sheet is more presentation bookkeeping than
    /// SwiftUI reliably tracks — it was leaving a modal on top with no working
    /// dismiss — and neither form was ever conceptually modal to begin with. What's left
    /// is two confirmation dialogs on one view, which is ordinary.
    public var body: some View {
        NavigationStack(path: path) {
            Form {
                repositorySection
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
                // (confirmed via screenshot) has no way to dismiss at all. Dispatches
                // rather than calling SwiftUI's `dismiss()`, so the store stays the only
                // thing that decides whether this sheet is up.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .navigationDestination(for: GitHubSyncRoute.self) { route in
                switch route {
                case .link: linkScreen
                case .editBranch: editBranchScreen
                }
            }
        }
        .confirmationDialog(
            "Unlink this repository?",
            isPresented: isConfirmingUnlink,
            titleVisibility: .visible
        ) {
            Button("Unlink", role: .destructive, action: onConfirmUnlink)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local articles are kept — you'll just need to link again to sync them.")
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

    @ViewBuilder
    private var repositorySection: some View {
        if isConfigured {
            Section("Repository") {
                LabeledContent("Repo", value: repoURL)
                LabeledContent("Branch", value: branch)
                Button("Edit Branch", action: onRequestEditBranch)
                Button("Unlink", role: .destructive, action: onRequestUnlink)
                    .disabled(isUnlinking)
            }
        } else {
            Section("Repository") {
                Text("Not linked to a GitHub repository yet.")
                    .foregroundStyle(.secondary)
                Button("Link Repository", action: onRequestLink)
            }
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
