import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexArchitecture
import SwiftRexOperators
import SwiftRexReactiveConcurrency
import SwiftUI

@Feature(strategy: .observationSimple)
public enum ArticleListFeature {
    public struct State: Sendable, Equatable {
        public var summaries: [ArticleSummary]
        public var searchText: String
        public var selectedSlug: String?
        /// `true` while the "New Article" name prompt is up — store state, not local
        /// SwiftUI `@State`, same convention as every other confirmation/prompt in this app.
        public var isCreatingArticle: Bool
        public var newArticleName: String
        public var createError: String?

        public init(
            summaries: [ArticleSummary] = [],
            searchText: String = "",
            selectedSlug: String? = nil,
            isCreatingArticle: Bool = false,
            newArticleName: String = "",
            createError: String? = nil
        ) {
            self.summaries = summaries
            self.searchText = searchText
            self.selectedSlug = selectedSlug
            self.isCreatingArticle = isCreatingArticle
            self.newArticleName = newArticleName
            self.createError = createError
        }
    }

    @Prisms
    public enum Action: Sendable {
        case start
        case loaded(Result<[ArticleSummary], ArticleEditorError>)
        case setSearchText(String)
        case select(ArticleSummary)
        case requestNewArticle
        case setNewArticleName(String)
        case cancelNewArticle
        case confirmNewArticle
        case created(Result<ArticleSummary, ArticleEditorError>)
        /// Not on `ViewAction` — `AppRootView` dispatches this directly (it holds the raw
        /// `MainStoreType`, not a `ArticleListFeature`-scoped `ViewStore`) when the user
        /// navigates back from the editor on iPhone, so the sidebar shows nothing
        /// selected rather than stale-highlighting whatever was last open.
        case clearSelection
    }

    public struct Environment: Sendable {
        public let listArticles: @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>
        public let createArticle: @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError>

        public init(
            listArticles: @escaping @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>,
            createArticle: @escaping @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError>
        ) {
            self.listArticles = listArticles
            self.createArticle = createArticle
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var items: [ArticleSummary]
        public var searchText: String
        public var selectedSlug: String?
        public var isCreatingArticle: Bool
        public var newArticleName: String
        public var createError: String?
    }

    @Prisms
    public enum ViewAction: Sendable {
        case onAppear
        case setSearchText(String)
        case select(ArticleSummary)
        case requestNewArticle
        case setNewArticleName(String)
        case cancelNewArticle
        case confirmNewArticle
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            let filtered = state.searchText.isEmpty
                ? state.summaries
                : state.summaries.filter {
                    $0.title.localizedCaseInsensitiveContains(state.searchText)
                        || $0.slug.localizedCaseInsensitiveContains(state.searchText)
                }
            return ViewState(
                items: filtered.sorted { $0.number < $1.number },
                searchText: state.searchText,
                selectedSlug: state.selectedSlug,
                isCreatingArticle: state.isCreatingArticle,
                newArticleName: state.newArticleName,
                createError: state.createError
            )
        }
    }

    public static let mapAction = Reader<Environment, @Sendable (ViewAction) -> Action> { _ in
        { viewAction in
            switch viewAction {
            case .onAppear: .start
            case .setSearchText(let text): .setSearchText(text)
            case .select(let summary): .select(summary)
            case .requestNewArticle: .requestNewArticle
            case .setNewArticleName(let name): .setNewArticleName(name)
            case .cancelNewArticle: .cancelNewArticle
            case .confirmNewArticle: .confirmNewArticle
            }
        }
    }

    public static func initialState(with _: Void) -> State { .init() }

    public static func behavior() -> Behavior<Action, State, Environment> {
        .handle { action, context in
            switch action {
            case .start:
                return .produce { ctx in
                    ctx.environment.listArticles()
                        .asEffect { Action.loaded($0) }
                }

            case .loaded(.success(let summaries)):
                return .reduce { $0.summaries = summaries }

            case .loaded(.failure):
                return .doNothing

            case .setSearchText(let text):
                return .reduce { $0.searchText = text }

            case .select(let summary):
                // Set immediately (optimistically), in the same pass as the tap — not
                // deferred until the editor confirms the document actually opened.
                // `NavigationSplitView`'s compact-width (iPhone) push to the detail
                // column is driven by this exact binding changing; waiting for the
                // async open to confirm first (the previous approach) meant the
                // selection update arrived a beat late and the push silently never
                // fired — tapping an article did nothing. `selectionSyncBehavior`
                // still re-asserts the confirmed slug once the open actually
                // completes, which also self-corrects the rare case where a switch
                // gets deferred/cancelled (an active chat session with unsaved
                // turns) — a briefly-wrong highlight in that edge case is a much
                // smaller problem than navigation never working at all.
                return .reduce { $0.selectedSlug = summary.slug }

            case .requestNewArticle:
                return .reduce { state in
                    state.isCreatingArticle = true
                    state.newArticleName = ""
                    state.createError = nil
                }

            case .setNewArticleName(let name):
                return .reduce { $0.newArticleName = name }

            case .cancelNewArticle:
                return .reduce { $0.isCreatingArticle = false }

            case .confirmNewArticle:
                guard let name = context.stateBefore?.newArticleName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .reduce { $0.createError = "Enter a name first." }
                }
                return .produce { ctx in ctx.environment.createArticle(name).asEffect { Action.created($0) } }

            // The actual "open it in the editor" step is a cross-feature concern (this
            // feature doesn't know about `ArticleEditorFeature`) — handled by
            // `AppFeature`'s `bridgeBehavior`, the same one `.select` already uses.
            case .created(.success(let summary)):
                return .reduce { state in
                    state.isCreatingArticle = false
                    state.createError = nil
                    state.summaries.append(summary)
                    // Same reasoning as `.select` above — set immediately so the
                    // detail column actually pushes on iPhone once the bridge opens it.
                    state.selectedSlug = summary.slug
                }

            case .created(.failure(let error)):
                return .reduce { $0.createError = error.readableDescription }

            case .clearSelection:
                return .reduce { $0.selectedSlug = nil }
            }
        }
    }

    public typealias Content = ArticleListView
}

extension ArticleEditorError {
    fileprivate var readableDescription: String {
        switch self {
        case .fileReadFailed(let path, let reason): "Couldn't read \(path): \(reason)"
        case .fileWriteFailed(let path, let reason): "Couldn't write \(path): \(reason)"
        case .parseFailed(let path, let reason): "Couldn't parse \(path): \(reason)"
        }
    }
}
