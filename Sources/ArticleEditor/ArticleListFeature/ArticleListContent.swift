import AppDomain
import SwiftUI

public struct ArticleListContent: View {
    let items: [ArticleSummary]
    let searchText: Binding<String>
    let selectedSlug: String?
    let isCreatingArticle: Binding<Bool>
    let newArticleName: Binding<String>
    let createError: String?
    let onSelect: (ArticleSummary) -> Void
    let onRequestNewArticle: () -> Void
    let onConfirmNewArticle: () -> Void

    public var body: some View {
        List(items, selection: Binding(
            get: { selectedSlug },
            set: { slug in
                if let slug, let match = items.first(where: { $0.slug == slug }) {
                    onSelect(match)
                }
            }
        )) { summary in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("#\(summary.number)")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 38, alignment: .trailing)
                    Text("— \(summary.title)")
                        .font(.body)
                }
                Text(summary.slug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }
            .tag(summary.slug)
        }
        .searchable(text: searchText, prompt: "Search articles")
        .navigationTitle("Articles")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onRequestNewArticle) {
                    Label("New Article", systemImage: "plus")
                }
            }
        }
        .alert("New Article", isPresented: isCreatingArticle) {
            TextField("Name", text: newArticleName)
            Button("Create", action: onConfirmNewArticle)
            Button("Cancel", role: .cancel) {}
        }
        // Not inside the alert's own `message:` — a native `Alert` dismisses itself the
        // instant ANY button is tapped, including "Create," so by the time an async
        // creation failure comes back the alert is already gone. A persistent banner
        // (same convention as `ArticleEditorContent`'s `saveError`) is the only place
        // that can actually show it.
        .safeAreaInset(edge: .bottom) {
            if let createError {
                Text(createError)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
    }
}
