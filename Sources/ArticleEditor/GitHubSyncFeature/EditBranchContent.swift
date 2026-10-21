import Localization
import SwiftUI
import Vitral
import VitralTokens

/// The only mutation allowed on an already-linked repo — see `LinkRepositoryContent`'s
/// doc comment for why `repoURL`/token aren't editable here.
public struct EditBranchContent: View {
    let branchInput: Binding<String>
    let isSaving: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    /// A pushed screen, so no `NavigationStack` of its own — it is rendered inside
    /// `GitHubSyncContent`'s stack, which supplies the bar this toolbar attaches to.
    public var body: some View {
        GlassList(backdrop: .grid(), rows: .padded) {
            Section {
                FieldText(L.Sync.baseBranch, text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text(L.Sync.baseBranch2)
            } footer: {
                Text(L.Sync.pullReadsFromThisBranch)
            }
        }
        .navigationTitle(L.Sync.editBaseBranch)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.Common.cancel, action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(L.Common.save)
                    }
                }
                .disabled(isSaving)
            }
        }
    }
}
