import Localization
import SwiftUI
import Vitral
import VitralTokens

/// The one-time repo/branch/token setup screen — everything here except the base branch
/// becomes unchangeable once linked (see `EditBranchContent`); changing repo or token means
/// unlinking and linking again.
public struct LinkRepositoryContent: View {
    let repoInput: Binding<String>
    let branchInput: Binding<String>
    let tokenInput: Binding<String>
    let isLinking: Bool
    let error: LocalizedStringResource?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private static let tokenCreationURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// A pushed screen, so no `NavigationStack` of its own — it is rendered inside
    /// `GitHubSyncContent`'s stack, which supplies the bar this toolbar attaches to.
    public var body: some View {
        GlassList(backdrop: .grid(), rows: .padded) {
            Section(L.Sync.repository) {
                TextField(L.Sync.ownerRepo, text: repoInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Text(L.Sync.alsoAcceptsAFullURL)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                TextField(L.Sync.baseBranch, text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text(L.Sync.baseBranch2)
            } footer: {
                Text(L.Sync.pullReadsNothingCommitted)
            }
            Section(L.Sync.personalAccessToken) {
                SecureField(L.Sync.token, text: tokenInput)
                Link(L.Sync.createATokenOnGithub, destination: Self.tokenCreationURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.Sync.onThatPageFillIn)
                    Text(L.Sync.repositoryAccessOnlySelectRepositories)
                    Text(L.Sync.permissionsContentsReadAndWrite)
                    Text(L.Sync.permissionsPullRequestsReadAnd)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.danger)
                }
            }
        }
        .navigationTitle(L.Sync.linkRepository)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.Common.cancel, action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isLinking {
                        ProgressView()
                    } else {
                        Text(L.Sync.link)
                    }
                }
                .disabled(isLinking)
            }
        }
    }
}
