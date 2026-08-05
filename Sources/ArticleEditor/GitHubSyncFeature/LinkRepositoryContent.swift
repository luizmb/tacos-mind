import SwiftUI

/// The one-time repo/branch/token setup screen — everything here except the base branch
/// becomes unchangeable once linked (see `EditBranchContent`); changing repo or token means
/// unlinking and linking again.
public struct LinkRepositoryContent: View {
    let repoInput: Binding<String>
    let branchInput: Binding<String>
    let tokenInput: Binding<String>
    let isLinking: Bool
    let error: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private static let tokenCreationURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// A pushed screen, so no `NavigationStack` of its own — it is rendered inside
    /// `GitHubSyncContent`'s stack, which supplies the bar this toolbar attaches to.
    public var body: some View {
        Form {
            Section("Repository") {
                TextField("owner/repo", text: repoInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Text(
                    "Also accepts a full GitHub URL. The repo is expected to have the same " +
                    "layout as this app's article data: an Articles/ folder at the root, " +
                    "with one JSON file per article."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                TextField("Base branch", text: branchInput)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Base Branch")
            } footer: {
                Text(
                    "Pull reads from this branch, and pushes open a pull request into it. " +
                    "Nothing is ever committed to it directly."
                )
            }
            Section("Personal Access Token") {
                SecureField("Token", text: tokenInput)
                Link("Create a token on GitHub", destination: Self.tokenCreationURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text("On that page, fill in:")
                    Text("• Repository access → Only select repositories → the one above")
                    Text("• Permissions → Contents → Read and write")
                    Text("• Permissions → Pull requests → Read and write (Push opens a PR)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Link Repository")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onConfirm) {
                    if isLinking {
                        ProgressView()
                    } else {
                        Text("Link")
                    }
                }
                .disabled(isLinking)
            }
        }
    }
}
