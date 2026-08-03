import AppDomain
import CoreFP
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
        /// Which row is highlighted. **Written only by the app's navigation reducer**,
        /// which re-derives it from the stack in the same synchronous step that changes
        /// the stack — so the highlight cannot disagree with what is actually open, and
        /// this feature never has to guess. It is stored rather than derived in
        /// `mapState` only because a feature's `mapState` cannot see the app's path.
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
        /// "Open this one." A pure intent: this feature has no idea what an editor is.
        /// `AppFeature`'s fold turns it into a navigation push, whose payload is shaped
        /// to match this one exactly so that wiring stays a single tacit line.
        case select(ArticleSummary)
        case requestNewArticle
        case setNewArticleName(String)
        case cancelNewArticle
        case confirmNewArticle
        case created(Result<ArticleSummary, ArticleEditorError>)
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

            // Purely a trigger for `AppFeature`'s fold, which pushes the editor and
            // re-derives `selectedSlug` from the stack in the same step. Setting the
            // highlight here too would put two writers on one field — exactly the split
            // that used to make the sidebar and the open article disagree.
            case .select:
                return .doNothing

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

            // A freshly created article opens exactly the way tapping it would — same
            // action, same gates, same push. Routing it through `.select` rather than
            // duplicating the app-level wiring means there is only ever one way in.
            case .created(.success(let summary)):
                return .reduce { state in
                    state.isCreatingArticle = false
                    state.createError = nil
                    state.summaries.append(summary)
                }
                .produce { _ in Self.immediateDispatch(.select(summary)) }

            case .created(.failure(let error)):
                return .reduce { $0.createError = error.readableDescription }
            }
        }
    }

    /// Fires `action` as an immediate follow-up dispatch from within a `.produce` step —
    /// the same "wrap a pure value in a one-shot Effect" trick used elsewhere in the app.
    private static func immediateDispatch(_ action: Action) -> Effect<Action> {
        let transform: @Sendable (()) -> Action = const(action)
        return Publisher<Void, Never>.just(()).asEffect(transform)
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
