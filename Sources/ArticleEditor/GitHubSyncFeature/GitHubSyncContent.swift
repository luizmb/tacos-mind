import AppDomain
import SwiftUI

public struct GitHubSyncContent: View {
    let path: Binding<[GitHubSyncRoute]>
    let isConfigured: Bool
    let repoURL: String
    let baseBranch: String
    let isPulling: Bool
    let lastPullOutcome: PullOutcome?
    let canOverwriteKeptLocal: Bool
    let isPushing: Bool
    let lastPushOutcome: PushOutcome?
    let lastError: String?
    let isConfirmingOverwrite: Binding<Bool>
    let onDone: () -> Void
    let onRequestLink: () -> Void
    let onRequestUnlink: () -> Void
    let onRequestEditBranch: () -> Void
    let onPull: () -> Void
    let onRequestOverwriteKeptLocal: () -> Void
    let onConfirmOverwriteKeptLocal: () -> Void
    let onPush: () -> Void

    let isConfirmingUnlink: Binding<Bool>
    let isUnlinking: Bool
    let onConfirmUnlink: () -> Void

    let linkScreen: LinkRepositoryContent
    let editBranchScreen: EditBranchContent
    let pushScreen: PushContent

    /// Link, Edit Branch and Push are **pushed**, not sheeted. Two sheets and two
    /// confirmation dialogs presented from inside a sheet is more presentation bookkeeping
    /// than SwiftUI reliably tracks — it was leaving a modal on top with no working
    /// dismiss — and none of these forms was ever conceptually modal to begin with. What's
    /// left is two confirmation dialogs on one view, which is ordinary.
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
                case .push: pushScreen
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
            "Discard your local changes?",
            isPresented: isConfirmingOverwrite,
            titleVisibility: .visible
        ) {
            Button("Overwrite with GitHub's Version", role: .destructive, action: onConfirmOverwriteKeptLocal)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let keptLocal = lastPullOutcome?.keptLocal, !keptLocal.isEmpty {
                Text("\(keptLocal.joined(separator: ", ")) will be replaced by what's on GitHub. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var repositorySection: some View {
        if isConfigured {
            Section("Repository") {
                LabeledContent("Repo", value: repoURL)
                LabeledContent("Base branch", value: baseBranch)
                Button("Edit Base Branch", action: onRequestEditBranch)
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
            if let lastPullOutcome {
                pullOutcomeView(lastPullOutcome)
            }
            actionRow(
                title: "Push to GitHub",
                systemImage: "arrow.up.circle",
                isBusy: isPushing,
                disabled: !isConfigured || isPushing,
                action: onPush
            )
            if let lastPushOutcome {
                pushOutcomeView(lastPushOutcome)
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

    /// Kept-local files are reported rather than prompted about — the pull already applied
    /// everything it safely could, and discarding local work is offered here as a
    /// deliberate second step instead of a gate on the common case.
    @ViewBuilder
    private func pullOutcomeView(_ outcome: PullOutcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if outcome.applied == 0, outcome.keptLocal.isEmpty {
                Text("Already up to date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if outcome.applied > 0 {
                Text("Pulled \(outcome.applied) article\(outcome.applied == 1 ? "" : "s").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !outcome.keptLocal.isEmpty {
                Text("Kept your local version of \(outcome.keptLocal.joined(separator: ", ")). Push to publish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if canOverwriteKeptLocal {
            Button("Overwrite Local with GitHub's Version", role: .destructive, action: onRequestOverwriteKeptLocal)
                .disabled(isPulling)
        }
    }

    @ViewBuilder
    private func pushOutcomeView(_ outcome: PushOutcome) -> some View {
        switch outcome {
        case .nothingToPush:
            Text("Nothing to push — everything's already on GitHub.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .pushed(let files, let branch, let commitURL, let prURL):
            VStack(alignment: .leading, spacing: 4) {
                Text("Pushed \(files.count) file(s) to \(branch): \(files.joined(separator: ", "))")
                    .font(.footnote)
                Link("View Pull Request", destination: prURL)
                Link("View Commit", destination: commitURL)
            }
        }
    }
}
