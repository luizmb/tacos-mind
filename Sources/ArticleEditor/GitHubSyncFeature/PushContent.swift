import Localization
import SwiftUI
import Vitral
import VitralTokens

/// Names the branch, commit and pull request a push will create. Every field arrives
/// pre-filled from the push preview, so confirming without touching anything is a valid
/// and expected way to use this screen.
public struct PushContent: View {
    let branchInput: Binding<String>
    let commitMessageInput: Binding<String>
    let prTitleInput: Binding<String>
    let prBodyInput: Binding<String>
    let fileCount: Int
    let baseBranch: String
    let isPushing: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    /// A pushed screen, so no `NavigationStack` of its own — it is rendered inside
    /// `GitHubSyncContent`'s stack, which supplies the bar this toolbar attaches to.
    public var body: some View {
        GlassList(backdrop: .grid(), rows: .padded) {
            Section {
                FieldText(L.Sync.branch, text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text(L.Sync.branch)
            } footer: {
                Text(L.Sync.aNewBranchOffReusing(baseBranch))
            }
            Section {
                FieldText(L.Sync.message, text: commitMessageInput)
            } header: {
                Text(L.Sync.commit)
            } footer: {
                Text(L.Sync.articleWillBeCommitted(fileCount))
            }
            Section {
                FieldText(L.Common.title, text: prTitleInput)
                FieldText(L.Sync.description, text: prBodyInput, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text(L.Sync.pullRequest)
            } footer: {
                Text(L.Sync.openedAgainst(baseBranch))
            }
        }
        .navigationTitle(L.Sync.pushToGithub)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.Common.cancel, action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isPushing {
                        ProgressView()
                    } else {
                        Text(L.Sync.push)
                    }
                }
                .disabled(isPushing || branchInput.wrappedValue.isEmpty)
            }
        }
    }
}
