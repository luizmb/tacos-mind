import AppDomain
import FileWatching
import Core
import Foundation
import GeneratorCore
import ReactiveConcurrency

/// The app's environment: file IO and process launching, all as plain closures — the
/// same convention PookiePayslip uses (a struct of closures, not a protocol).
public struct World: Sendable {
    public var currentDate: @Sendable () -> Date
    public var articlesDirectory: @Sendable () -> URL
    public var repositoryRoot: @Sendable () -> URL
    /// Injected rather than constructing `JSONDecoder()`/`JSONEncoder()` ad hoc where
    /// needed — same `DataDecoderFactory`/`DataEncoderFactory` convention as
    /// PookiePayslip's `World`. `.live` sets these to plain `JSONDecoder`/`JSONEncoder`;
    /// `.mock` can substitute a different strategy (or a failing one) for tests.
    public var decoder: any DataDecoderFactory & Sendable
    public var encoder: any DataEncoderFactory & Sendable

    public var listArticles: @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>
    /// Creates a new, minimal article file (`title`/`slug` both set to the given name,
    /// `.text` emphasis, next available `number`, no tags/blocks) and writes it to
    /// `articlesDirectory()/{name}.json`. Fails if the name is blank or already taken.
    public var createArticle: @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError>
    public var openDocument: @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError>
    public var saveDocument: @Sendable (OpenDocument) -> Publisher<String, ArticleEditorError>
    public var watchFile: @Sendable (URL) -> Publisher<FileWatchEvent, Never>
    public var checkDiskHash: @Sendable (URL) -> Publisher<String, ArticleEditorError>
    public var parseDiskArticle: @Sendable (URL) -> Publisher<Article, ArticleEditorError>
    /// Regenerates just this one article's HTML (by slug) into `dist/`, ensuring the
    /// stylesheet/fonts scaffold exists first without wiping any existing `dist/` content
    /// (unlike `generateAllArticles`) — Cmd+R must not blow away a build the user is
    /// currently previewing. Yields the article's preview URL once written.
    public var generateArticle: @Sendable (String) -> Publisher<URL, ArticleEditorError>
    /// Regenerates the entire site into `dist/` — wipes and recreates it first, then
    /// writes the stylesheet, fonts, home page, every publishable article, and every tag
    /// page. Mirrors `Generator`'s own `main.swift` pipeline exactly, just run in-process.
    public var generateAllArticles: @Sendable () -> Publisher<Void, ArticleEditorError>
    /// Opens `url` in the system browser (Safari) — the article preview mechanism. A
    /// fire-and-forget boundary call, not a `Publisher`, since there's no result to await;
    /// `@MainActor` because it wraps an AppKit/UIKit call, same as `completeTermination`.
    public var openInBrowser: @MainActor @Sendable (URL) -> Void
    /// Presents the "unsaved changes" quit alert (macOS only — see `AppDelegate`) and
    /// resolves with the user's choice. A no-op stand-in on iOS: `.quitRequested` is only
    /// ever dispatched by the macOS `AppDelegate`, so this is never actually called there.
    public var confirmQuit: @Sendable () -> Publisher<QuitAlertChoice, Never>
    /// Tells AppKit whether to actually proceed with termination (macOS only — the other
    /// half of `applicationShouldTerminate`'s `.terminateLater`). A no-op on iOS.
    public var completeTermination: @MainActor @Sendable (Bool) -> Void

    /// `true` when the on-device language model (Apple Intelligence) is available — used
    /// to hide/disable the chat entry point gracefully rather than let a call fail.
    public var isAssistantAvailable: @Sendable () -> Bool
    /// Fires the on-device model with `request.prompt`, seeded by `request.instructions`
    /// (Brainstorming plus recent turns). `.chunk` yields carry the reply's cumulative
    /// text so far; a `.finished` value always closes the stream (see `ChatStreamEvent`'s
    /// doc) — a Command, not a long-lived subscription, even though it yields repeatedly.
    public var chatRespond: @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError>
    /// Speaks `text` aloud; completes when finished (or stopped early). A Command.
    public var speak: @Sendable (String) -> Publisher<Void, SpeechError>
    /// Starts listening on the microphone and yields live transcript updates until the
    /// caller cancels — a long-lived Subscription (see `ArticleEditorFeature`'s
    /// `fileWatchSupervisor` for the same shape), not a one-shot Command.
    public var startListening: @Sendable () -> Publisher<TranscriptUpdate, SpeechError>

    /// Loads persisted GitHub sync settings, if any were ever saved — `nil` on first
    /// launch, or after `unlinkRepository`. Infallible: a corrupt/missing store just
    /// reads as "not configured yet."
    public var loadGitHubSettings: @Sendable () -> Publisher<GitHubSettings?, Never>
    /// Only called from the one-time link setup — verifies `settings` (repo access +
    /// token validity) via a live API call before persisting anything. Only `baseBranch`
    /// can be changed after this via `updateBranch`; changing `repoURL`/`token` means
    /// `unlinkRepository` then linking again.
    public var linkRepository: @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>
    /// The only mutation allowed on an already-linked repo — leaves `repoURL`/token alone.
    public var updateBranch: @Sendable (String) -> Publisher<Void, GitHubError>
    /// Clears the linked repo entirely: `repoURL`/`baseBranch` and the Keychain token.
    /// Local articles are untouched — this only forgets where they sync to.
    public var unlinkRepository: @Sendable () -> Publisher<Void, GitHubError>
    /// Whether `articlesDirectory()` currently has zero `.json` files — decides what a
    /// freshly-linked repo's first sync does (see `GitHubSyncFeature.firstSyncDecided`).
    public var isArticlesDirEmpty: @Sendable () -> Publisher<Bool, Never>
    /// Computes what a pull *would* do — nothing is written to disk yet. Carries the
    /// already-downloaded bytes so a subsequent `applyPull` never re-fetches.
    public var previewPull: @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>
    /// Writes every file in `preview.toAdd`/`preview.toUpdate` to `articlesDirectory()`.
    /// Returns the number of files written.
    public var applyPull: @Sendable (PullPreview) -> Publisher<Int, GitHubError>
    /// Diffs every local article against `settings.baseBranch` and reports which differ,
    /// carrying their local bytes so `performPush` never re-reads them. Nothing is created
    /// on GitHub — this is what pre-fills the push form, and what tells the caller there's
    /// nothing to push before any form is shown at all.
    public var previewPush: @Sendable (GitHubSettings) -> Publisher<PushPreview, GitHubError>
    /// Commits `preview.files` as one atomic commit (Git Data API: blob/tree/commit/ref)
    /// onto `request.branch` — creating that branch off the base branch's tip if it's new,
    /// or appending to it if a previous push already made it — then opens a pull request
    /// into `settings.baseBranch`. Reuses the branch's already-open PR if there is one, so
    /// pushing the same branch name twice appends rather than erroring. The base branch is
    /// never written to directly.
    public var performPush: @Sendable (GitHubSettings, PushRequest, PushPreview) -> Publisher<PushOutcome, GitHubError>

    public init(
        currentDate: @escaping @Sendable () -> Date,
        articlesDirectory: @escaping @Sendable () -> URL,
        repositoryRoot: @escaping @Sendable () -> URL,
        decoder: any DataDecoderFactory & Sendable,
        encoder: any DataEncoderFactory & Sendable,
        listArticles: @escaping @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>,
        createArticle: @escaping @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError>,
        openDocument: @escaping @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError>,
        saveDocument: @escaping @Sendable (OpenDocument) -> Publisher<String, ArticleEditorError>,
        watchFile: @escaping @Sendable (URL) -> Publisher<FileWatchEvent, Never>,
        checkDiskHash: @escaping @Sendable (URL) -> Publisher<String, ArticleEditorError>,
        parseDiskArticle: @escaping @Sendable (URL) -> Publisher<Article, ArticleEditorError>,
        generateArticle: @escaping @Sendable (String) -> Publisher<URL, ArticleEditorError>,
        generateAllArticles: @escaping @Sendable () -> Publisher<Void, ArticleEditorError>,
        openInBrowser: @escaping @MainActor @Sendable (URL) -> Void,
        confirmQuit: @escaping @Sendable () -> Publisher<QuitAlertChoice, Never>,
        completeTermination: @escaping @MainActor @Sendable (Bool) -> Void,
        isAssistantAvailable: @escaping @Sendable () -> Bool,
        chatRespond: @escaping @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError>,
        speak: @escaping @Sendable (String) -> Publisher<Void, SpeechError>,
        startListening: @escaping @Sendable () -> Publisher<TranscriptUpdate, SpeechError>,
        loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never>,
        linkRepository: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>,
        updateBranch: @escaping @Sendable (String) -> Publisher<Void, GitHubError>,
        unlinkRepository: @escaping @Sendable () -> Publisher<Void, GitHubError>,
        isArticlesDirEmpty: @escaping @Sendable () -> Publisher<Bool, Never>,
        previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>,
        applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError>,
        previewPush: @escaping @Sendable (GitHubSettings) -> Publisher<PushPreview, GitHubError>,
        performPush: @escaping @Sendable (GitHubSettings, PushRequest, PushPreview) -> Publisher<PushOutcome, GitHubError>
    ) {
        self.currentDate = currentDate
        self.articlesDirectory = articlesDirectory
        self.repositoryRoot = repositoryRoot
        self.decoder = decoder
        self.encoder = encoder
        self.listArticles = listArticles
        self.createArticle = createArticle
        self.openDocument = openDocument
        self.saveDocument = saveDocument
        self.watchFile = watchFile
        self.checkDiskHash = checkDiskHash
        self.parseDiskArticle = parseDiskArticle
        self.generateArticle = generateArticle
        self.generateAllArticles = generateAllArticles
        self.openInBrowser = openInBrowser
        self.confirmQuit = confirmQuit
        self.completeTermination = completeTermination
        self.isAssistantAvailable = isAssistantAvailable
        self.chatRespond = chatRespond
        self.speak = speak
        self.startListening = startListening
        self.loadGitHubSettings = loadGitHubSettings
        self.linkRepository = linkRepository
        self.updateBranch = updateBranch
        self.unlinkRepository = unlinkRepository
        self.isArticlesDirEmpty = isArticlesDirEmpty
        self.previewPull = previewPull
        self.applyPull = applyPull
        self.previewPush = previewPush
        self.performPush = performPush
    }
}
