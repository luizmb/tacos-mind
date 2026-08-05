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
            Section {
                TextField("Base branch", text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Base Branch")
            } footer: {
                Text("Pull reads from this branch, and pushes open a pull request into it.")
            }
        }
        .navigationTitle("Edit Base Branch")
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
