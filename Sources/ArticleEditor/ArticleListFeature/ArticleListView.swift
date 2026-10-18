import AppDomain
import SwiftRexArchitecture
import SwiftUI

@BoundTo(ArticleListFeature.self)
public struct ArticleListView: View {
    public var body: some View {
        ArticleListContent(
            items: viewStore.state.items.value,
            searchText: viewStore.binding(.state(\.searchText).action(\.setSearchText)),
            selectedSlug: viewStore.state.selectedSlug,
            isCreatingArticle: viewStore.binding(.state(\.isCreatingArticle).action(review: { _ in .cancelNewArticle })),
            newArticleName: viewStore.binding(.state(\.newArticleName).action(\.setNewArticleName)),
            createError: viewStore.state.createError,
            onSelect: { viewStore.dispatch(.select($0)) },
            onRequestNewArticle: { viewStore.dispatch(.requestNewArticle) },
            onConfirmNewArticle: { viewStore.dispatch(.confirmNewArticle) }
        )
        .onAppear { viewStore.dispatch(.onAppear) }
    }
}
