import SwiftUI

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
        Form {
            Section {
                TextField("Branch", text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Branch")
            } footer: {
                Text("A new branch off \(baseBranch). Reusing an existing name adds to its pull request.")
            }
            Section {
                TextField("Message", text: commitMessageInput)
            } header: {
                Text("Commit")
            } footer: {
                Text("\(fileCount) article\(fileCount == 1 ? "" : "s") will be committed.")
            }
            Section {
                TextField("Title", text: prTitleInput)
                TextField("Description", text: prBodyInput, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Pull Request")
            } footer: {
                Text("Opened against \(baseBranch).")
            }
        }
        .navigationTitle("Push to GitHub")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isPushing {
                        ProgressView()
                    } else {
                        Text("Push")
                    }
                }
                .disabled(isPushing || branchInput.wrappedValue.isEmpty)
            }
        }
    }
}
