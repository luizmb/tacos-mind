import AppDomain
import FileWatching
import Core
import Foundation
import GeneratorCore
import ReactiveConcurrency

extension World {
    public static func mock(
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
        articlesDirectory: @escaping @Sendable () -> URL = { URL(fileURLWithPath: "/tmp/mock-articles") },
        repositoryRoot: @escaping @Sendable () -> URL = { URL(fileURLWithPath: "/tmp/mock-repo") },
        decoder: any DataDecoderFactory & Sendable = JSONDecoder(),
        encoder: any DataEncoderFactory & Sendable = JSONEncoder(),
        listArticles: @escaping @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError> = { .just([]) },
        createArticle: @escaping @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError> = { name in
            .just(ArticleSummary(url: URL(fileURLWithPath: "/tmp/mock-articles/\(name).json"), slug: name, title: name, number: 1))
        },
        openDocument: @escaping @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError> = { url in
            .fail(.fileReadFailed(path: url.path, reason: "mock: not configured"))
        },
        saveDocument: @escaping @Sendable (OpenDocument) -> Publisher<String, ArticleEditorError> = { _ in
            .just("mock-hash")
        },
        watchFile: @escaping @Sendable (URL) -> Publisher<FileWatchEvent, Never> = { _ in .empty() },
        checkDiskHash: @escaping @Sendable (URL) -> Publisher<String, ArticleEditorError> = { _ in .just("mock-hash") },
        parseDiskArticle: @escaping @Sendable (URL) -> Publisher<Article, ArticleEditorError> = { url in
            .fail(.fileReadFailed(path: url.path, reason: "mock: not configured"))
        },
        generateArticle: @escaping @Sendable (String) -> Publisher<URL, ArticleEditorError> = { slug in
            .just(URL(fileURLWithPath: "/tmp/mock-preview/articles/\(slug).html"))
        },
        generateAllArticles: @escaping @Sendable () -> Publisher<Void, ArticleEditorError> = { .just(()) },
        openInBrowser: @escaping @MainActor @Sendable (URL) -> Void = { _ in },
        confirmQuit: @escaping @Sendable () -> Publisher<QuitAlertChoice, Never> = { .just(.cancel) },
        completeTermination: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        isAssistantAvailable: @escaping @Sendable () -> Bool = { true },
        chatRespond: @escaping @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError> = { _ in
            Publisher { continuation throws(ChatError) in continuation.yieldAll([.chunk("mock reply"), .finished]) }
        },
        speak: @escaping @Sendable (String) -> Publisher<Void, SpeechError> = { _ in .just(()) },
        startListening: @escaping @Sendable () -> Publisher<TranscriptUpdate, SpeechError> = { .empty() },
        loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never> = { .just(nil) },
        saveGitHubSettings: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError> = { _ in .just(()) },
        previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError> = { _ in
            .just(PullPreview(toAdd: [], toUpdate: [], localOnlyChanges: []))
        },
        applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError> = { _ in .just(0) },
        commitLocalChanges: @escaping @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError> = { _ in
            .just(.nothingToCommit)
        },
        openPullRequest: @escaping @Sendable (GitHubSettings) -> Publisher<URL, GitHubError> = { _ in
            .just(URL(fileURLWithPath: "/tmp/mock-pr"))
        }
    ) -> World {
        World(
            currentDate: currentDate,
            articlesDirectory: articlesDirectory,
            repositoryRoot: repositoryRoot,
            decoder: decoder,
            encoder: encoder,
            listArticles: listArticles,
            createArticle: createArticle,
            openDocument: openDocument,
            saveDocument: saveDocument,
            watchFile: watchFile,
            checkDiskHash: checkDiskHash,
            parseDiskArticle: parseDiskArticle,
            generateArticle: generateArticle,
            generateAllArticles: generateAllArticles,
            openInBrowser: openInBrowser,
            confirmQuit: confirmQuit,
            completeTermination: completeTermination,
            isAssistantAvailable: isAssistantAvailable,
            chatRespond: chatRespond,
            speak: speak,
            startListening: startListening,
            loadGitHubSettings: loadGitHubSettings,
            saveGitHubSettings: saveGitHubSettings,
            previewPull: previewPull,
            applyPull: applyPull,
            commitLocalChanges: commitLocalChanges,
            openPullRequest: openPullRequest
        )
    }
}
