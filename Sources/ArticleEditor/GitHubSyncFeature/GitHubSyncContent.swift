import Localization
import AppDomain
import SwiftUI
import Vitral
import VitralTokens

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
    let lastError: LocalizedStringResource?
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
            GlassList(backdrop: .grid(), rows: .padded) {
                repositorySection
                actionsSection
                if let lastError {
                    Section {
                        Text(lastError)
                            .foregroundStyle(.danger)
                    }
                }
            }
            .navigationTitle(L.Common.githubSync)
            .toolbar {
                // macOS sheets get no close affordance for free — without this the sheet
                // (confirmed via screenshot) has no way to dismiss at all. Dispatches
                // rather than calling SwiftUI's `dismiss()`, so the store stays the only
                // thing that decides whether this sheet is up.
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.Common.done, action: onDone)
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
            L.Sync.unlinkThisRepository,
            isPresented: isConfirmingUnlink,
            titleVisibility: .visible
        ) {
            Button(L.Sync.unlink, role: .destructive, action: onConfirmUnlink)
            Button(L.Common.cancel, role: .cancel) {}
        } message: {
            Text(L.Sync.localArticlesAreKeptYoull)
        }
        .confirmationDialog(
            L.Sync.discardYourLocalChanges,
            isPresented: isConfirmingOverwrite,
            titleVisibility: .visible
        ) {
            Button(L.Sync.overwriteWithGithubsVersion, role: .destructive, action: onConfirmOverwriteKeptLocal)
            Button(L.Common.cancel, role: .cancel) {}
        } message: {
            if let keptLocal = lastPullOutcome?.keptLocal, !keptLocal.isEmpty {
                Text(L.Sync.willBeReplacedByWhats(keptLocal.joined(separator: ", ")))
            }
        }
    }

    @ViewBuilder
    private var repositorySection: some View {
        if isConfigured {
            Section(L.Sync.repository) {
                FieldValue(L.Sync.repo, value: Text(verbatim: repoURL))
                FieldValue(L.Sync.baseBranch, value: Text(verbatim: baseBranch))
                Button(L.Sync.editBaseBranch, action: onRequestEditBranch)
                Button(L.Sync.unlink, role: .destructive, action: onRequestUnlink)
                    .disabled(isUnlinking)
            }
        } else {
            Section(L.Sync.repository) {
                Text(L.Sync.notLinkedToAGithub)
                    .foregroundStyle(.secondary)
                Button(L.Sync.linkRepository, action: onRequestLink)
            }
        }
    }

    private var actionsSection: some View {
        Section(L.Sync.actions) {
            actionRow(
                title: L.Sync.pullFromGithub,
                systemImage: "arrow.down.circle",
                isBusy: isPulling,
                disabled: !isConfigured || isPulling,
                action: onPull
            )
            if let lastPullOutcome {
                pullOutcomeView(lastPullOutcome)
            }
            actionRow(
                title: L.Sync.pushToGithub,
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
        title: LocalizedStringKey,
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
                Text(L.Sync.alreadyUpToDate)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if outcome.applied > 0 {
                Text(L.Sync.pulledArticle(outcome.applied))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !outcome.keptLocal.isEmpty {
                Text(L.Sync.keptYourLocalVersionOf(outcome.keptLocal.joined(separator: ", ")))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if canOverwriteKeptLocal {
            Button(L.Sync.overwriteLocalWithGithubsVersion, role: .destructive, action: onRequestOverwriteKeptLocal)
                .disabled(isPulling)
        }
    }

    @ViewBuilder
    private func pushOutcomeView(_ outcome: PushOutcome) -> some View {
        switch outcome {
        case .nothingToPush:
            Text(L.Sync.nothingToPushEverythingsAlready)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .pushed(let files, let branch, let commitURL, let prURL):
            VStack(alignment: .leading, spacing: 4) {
                Text(L.Sync.pushedFileSTo(files.count, branch, files.joined(separator: ", ")))
                    .font(.footnote)
                Link(L.Sync.viewPullRequest, destination: prURL)
                Link(L.Sync.viewCommit, destination: commitURL)
            }
        }
    }
}
