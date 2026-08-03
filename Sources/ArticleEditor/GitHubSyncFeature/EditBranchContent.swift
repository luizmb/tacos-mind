import SwiftUI

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
        Form {
            Section("Branch") {
                TextField("Branch", text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Edit Branch")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
    }
}
