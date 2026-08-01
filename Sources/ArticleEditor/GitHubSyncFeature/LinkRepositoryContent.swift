import SwiftUI

/// The one-time repo/branch/token setup screen — everything here except `branch` becomes
/// unchangeable once linked (see `EditBranchContent`); changing repo or token means
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

    public var body: some View {
        NavigationStack {
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
                Section("Branch") {
                    TextField("Branch", text: branchInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }
                Section("Personal Access Token") {
                    SecureField("Token", text: tokenInput)
                    Link("Create a token on GitHub", destination: Self.tokenCreationURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On that page, fill in:")
                        Text("• Repository access → Only select repositories → the one above")
                        Text("• Permissions → Contents → Read and write")
                        Text("• Permissions → Pull requests → Read and write (for Open Pull Request)")
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
}
