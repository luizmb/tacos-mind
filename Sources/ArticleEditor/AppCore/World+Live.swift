import AppDomain
import FileWatching
// AVFoundation's audio types (`AVAudioPCMBuffer`, `AVAudioConverterInputBlock`, etc.)
// predate Swift's Sendable audit — a captured `AVAudioPCMBuffer` inside the converter's
// `@Sendable` input block below is genuinely safe (single audio-thread callback, consumed
// synchronously within one `convert()` call), but the compiler can't verify that itself.
@preconcurrency import AVFoundation
import Core
import CoreMedia
import CryptoKit
import Foundation
import FoundationModels
import GeneratorCore
import NetworkClient
import os
import ReactiveConcurrency
import Speech

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension World {
    public static let real: World = {
        // `homeDirectoryForCurrentUser` doesn't exist on iOS (sandboxed apps have no
        // shared home directory), and reaching an arbitrary path like this repo's
        // clone location isn't possible there anyway without a document picker and
        // security-scoped bookmarks — a real feature of its own, out of scope for this
        // pass. iOS/iPadOS falls back to the app's own container for now; opening a
        // real article file on those platforms needs that follow-up first.
        #if os(macOS)
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/ios.lu")
        #else
        let root = URL.documentsDirectory
        #endif
        let articlesDir = root.appendingPathComponent("Articles")
        let distDir = root.appendingPathComponent("dist")

        let jsonDecoder = JSONDecoder()
        let jsonEncoder = JSONEncoder()
        // Pretty-printed and key-sorted, not the default compact/unsorted output — these
        // files live in git and get reviewed/diffed, so a stable, readable shape matters
        // more than a few saved bytes.
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Specialized once here (matching PookiePayslip's convention: the generic
        // decoder/encoder factory is injected, but each concrete (Input) -> Data /
        // Data -> Output conversion is built once at the composition root, not
        // reconstructed per call).
        let decodeArticle = jsonDecoder.dataDecoder(for: Article.self)
        let encodeArticle = jsonEncoder.dataEncoder(for: Article.self)

        // Shared by `generateArticle`/`generateAllArticles` — the same load-and-sort
        // `Generator`'s own `main.swift` does (filenames carry no ordering; `number` is
        // the source of truth for reading order).
        @Sendable func loadAllArticles() -> Result<[Article], ArticleEditorError> {
            // On a fresh install (most visibly iOS, whose sandboxed Documents directory
            // starts genuinely empty — nothing has ever been written there), `Articles/`
            // itself doesn't exist yet. That's "zero articles," not a read failure.
            guard FileManager.default.fileExists(atPath: articlesDir.path) else {
                return .success([])
            }
            let files: [URL]
            switch Result(catching: {
                try FileManager.default.contentsOfDirectory(at: articlesDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
            }) {
            case .success(let found): files = found
            case .failure(let error): return .failure(.fileReadFailed(path: articlesDir.path, reason: error.localizedDescription))
            }
            var articles: [Article] = []
            for file in files {
                guard let data = try? Data(contentsOf: file) else {
                    return .failure(.fileReadFailed(path: file.path, reason: "couldn't read file"))
                }
                switch decodeArticle(data) {
                case .success(let article): articles.append(article)
                case .failure(let error): return .failure(.parseFailed(path: file.path, reason: error.localizedDescription))
                }
            }
            return .success(articles.sorted { $0.number < $1.number })
        }

        // `GeneratorError` (from `GeneratorCore`, a pure/portable module with no notion of
        // this app's own error type) maps onto the existing `ArticleEditorError` cases
        // rather than introducing a second Failure type into this Environment.
        @Sendable func mapGeneratorError(_ error: GeneratorError) -> ArticleEditorError {
            switch error {
            case .directoryCreationFailed(let path, let reason): .fileWriteFailed(path: path, reason: reason)
            case .directoryRemovalFailed(let path, let reason): .fileWriteFailed(path: path, reason: reason)
            case .fileWriteFailed(let path, let reason): .fileWriteFailed(path: path, reason: reason)
            case .fileCopyFailed(let from, let to, let reason): .fileWriteFailed(path: to, reason: "copy from \(from) failed: \(reason)")
            }
        }

        @Sendable func run(_ result: Result<Void, GeneratorError>) throws(ArticleEditorError) {
            if case .failure(let error) = result { throw mapGeneratorError(error) }
        }

        return World(
            currentDate: { Date() },
            articlesDirectory: { articlesDir },
            repositoryRoot: { root },
            decoder: jsonDecoder,
            encoder: jsonEncoder,
            listArticles: {
                Publisher { continuation throws(ArticleEditorError) in
                    // Same reasoning as `loadAllArticles` — a fresh install (iOS especially)
                    // has never written to `Articles/`, so it doesn't exist yet.
                    guard FileManager.default.fileExists(atPath: articlesDir.path) else {
                        continuation.yield([])
                        return
                    }
                    let files: [URL]
                    do {
                        files = try FileManager.default.contentsOfDirectory(at: articlesDir, includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension == "json" }
                    } catch {
                        throw .fileReadFailed(path: articlesDir.path, reason: error.localizedDescription)
                    }
                    var summaries: [ArticleSummary] = []
                    for file in files {
                        guard let data = try? Data(contentsOf: file) else { continue }
                        guard case .success(let article) = decodeArticle(data) else { continue }
                        summaries.append(ArticleSummary(url: file, slug: article.slug, title: article.title, number: article.number))
                    }
                    continuation.yield(summaries)
                }
            },
            createArticle: { name in
                Publisher { continuation throws(ArticleEditorError) in
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else {
                        throw .fileWriteFailed(path: trimmedName, reason: "Name can't be empty")
                    }
                    let fileURL = articlesDir.appendingPathComponent("\(trimmedName).json")
                    guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                        throw .fileWriteFailed(path: fileURL.path, reason: "An article named \"\(trimmedName)\" already exists")
                    }
                    let existingNumbers: [Int]
                    switch loadAllArticles() {
                    case .success(let articles): existingNumbers = articles.map(\.number)
                    case .failure(let error): throw error
                    }
                    let nextNumber = (existingNumbers.max() ?? 0) + 1
                    let article = Article(title: trimmedName, slug: trimmedName, emphasis: .text, number: nextNumber, blocks: [])
                    let data: Data
                    switch encodeArticle(article) {
                    case .success(let encoded): data = encoded
                    case .failure(let error): throw .parseFailed(path: fileURL.path, reason: error.localizedDescription)
                    }
                    do {
                        // `Articles/` may not exist yet (a fresh install, most visibly on
                        // iOS) — this is the first thing that ever writes into it.
                        try FileManager.default.createDirectory(at: articlesDir, withIntermediateDirectories: true)
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        throw .fileWriteFailed(path: fileURL.path, reason: error.localizedDescription)
                    }
                    continuation.yield(ArticleSummary(url: fileURL, slug: trimmedName, title: trimmedName, number: nextNumber))
                }
            },
            openDocument: { url in
                Publisher { continuation throws(ArticleEditorError) in
                    let data: Data
                    do {
                        data = try Data(contentsOf: url)
                    } catch {
                        throw .fileReadFailed(path: url.path, reason: error.localizedDescription)
                    }
                    let article: Article
                    switch decodeArticle(data) {
                    case .success(let decoded): article = decoded
                    case .failure(let error): throw .parseFailed(path: url.path, reason: error.localizedDescription)
                    }
                    // No node-identity to preserve across a JSON re-encode (unlike the old
                    // SwiftSyntax splice, nothing here tracks "this block's source range
                    // didn't change") — every block just gets a fresh editor-only UUID.
                    let blockIDs = article.blocks.map { _ in UUID() }
                    continuation.yield((article: article, blockIDs: blockIDs))
                }
            },
            saveDocument: { document in
                Publisher { continuation throws(ArticleEditorError) in
                    let data: Data
                    switch encodeArticle(document.currentArticle) {
                    case .success(let encoded): data = encoded
                    case .failure(let error): throw .parseFailed(path: document.url.path, reason: error.localizedDescription)
                    }
                    do {
                        try data.write(to: document.url, options: .atomic)
                    } catch {
                        throw .fileWriteFailed(path: document.url.path, reason: error.localizedDescription)
                    }
                    continuation.yield(sha256Hex(of: data))
                }
            },
            watchFile: { url in FileWatcher.watch(url: url) },
            checkDiskHash: { url in
                Publisher { continuation throws(ArticleEditorError) in
                    let data: Data
                    do {
                        data = try Data(contentsOf: url)
                    } catch {
                        throw .fileReadFailed(path: url.path, reason: error.localizedDescription)
                    }
                    continuation.yield(sha256Hex(of: data))
                }
            },
            parseDiskArticle: { url in
                Publisher { continuation throws(ArticleEditorError) in
                    let data: Data
                    do {
                        data = try Data(contentsOf: url)
                    } catch {
                        throw .fileReadFailed(path: url.path, reason: error.localizedDescription)
                    }
                    switch decodeArticle(data) {
                    case .success(let article): continuation.yield(article)
                    case .failure(let error): throw .parseFailed(path: url.path, reason: error.localizedDescription)
                    }
                }
            },
            generateArticle: { slug in
                Publisher { continuation throws(ArticleEditorError) in
                    let allArticles: [Article]
                    switch loadAllArticles() {
                    case .success(let loaded): allArticles = loaded
                    case .failure(let error): throw error
                    }
                    let articles = publishableArticles(allArticles, includeDrafts: true)
                    guard let article = articles.first(where: { $0.slug == slug }) else {
                        throw .fileReadFailed(path: slug, reason: "no publishable article with this slug")
                    }
                    let links = linkTable(all: allArticles, published: articles)
                    let tags = usedTags(in: articles)
                    let distPath = distDir.path

                    // Ensures the scaffold exists without wiping any existing `dist/`
                    // content — Cmd+R regenerates just this one article, it must not
                    // blow away a build the user is currently previewing.
                    if !FileManager.default.fileExists(atPath: "\(distPath)/style.css") {
                        try run(GeneratorCore.World.live.createDirectory(distPath))
                        try run(writeStylesheet(to: "\(distPath)/style.css").runReader(.live))
                        try run(writeFonts(into: "\(distPath)/fonts").runReader(.live))
                    }
                    try run(writeArticle(article, into: "\(distPath)/articles", links: links, tags: tags).runReader(.live))

                    PreviewServer.ensureStarted(servingDirectory: distDir)

                    var components = URLComponents()
                    components.scheme = "http"
                    components.host = "127.0.0.1"
                    components.port = PreviewServer.port
                    components.path = "/articles/\(slug).html"
                    guard let previewURL = components.url else {
                        throw .fileWriteFailed(path: slug, reason: "couldn't construct the preview URL")
                    }
                    continuation.yield(previewURL)
                }
            },
            generateAllArticles: {
                Publisher { continuation throws(ArticleEditorError) in
                    let allArticles: [Article]
                    switch loadAllArticles() {
                    case .success(let loaded): allArticles = loaded
                    case .failure(let error): throw error
                    }
                    let articles = publishableArticles(allArticles, includeDrafts: true)
                    let links = linkTable(all: allArticles, published: articles)
                    let tags = usedTags(in: articles)
                    let distPath = distDir.path

                    try run(prepareSite(at: distPath).runReader(.live))
                    try run(writeStylesheet(to: "\(distPath)/style.css").runReader(.live))
                    try run(writeFonts(into: "\(distPath)/fonts").runReader(.live))
                    try run(writeHomePage(articles, tags: tags, to: "\(distPath)/index.html").runReader(.live))
                    for article in articles {
                        try run(writeArticle(article, into: "\(distPath)/articles", links: links, tags: tags).runReader(.live))
                    }
                    for tag in tags {
                        try run(writeTagPage(tag, articles: articles, tags: tags, into: "\(distPath)/tags").runReader(.live))
                    }
                    continuation.yield(())
                }
            },
            openInBrowser: { url in
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #elseif os(iOS)
                UIApplication.shared.open(url)
                #endif
            },
            confirmQuit: {
                Publisher { continuation in
                    #if os(macOS)
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Unsaved Changes"
                        alert.informativeText = "Do you want to save your changes before quitting?"
                        alert.addButton(withTitle: "Save and Quit")
                        alert.addButton(withTitle: "Discard and Quit")
                        alert.addButton(withTitle: "Cancel")
                        switch alert.runModal() {
                        case .alertFirstButtonReturn: continuation.yield(.saveAndQuit)
                        case .alertSecondButtonReturn: continuation.yield(.discardAndQuit)
                        default: continuation.yield(.cancel)
                        }
                    }
                    #else
                    // `.quitRequested` is only ever dispatched by the macOS AppDelegate,
                    // so this path is never actually reached on iOS.
                    continuation.yield(.cancel)
                    #endif
                }
            },
            completeTermination: { shouldTerminate in
                #if os(macOS)
                NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
                #endif
            },
            isAssistantAvailable: { SystemLanguageModel.default.isAvailable },
            chatRespond: { request in
                Publisher { continuation throws(ChatError) in
                    guard SystemLanguageModel.default.isAvailable else { throw .modelUnavailable }
                    let session = LanguageModelSession(instructions: request.instructions)
                    do {
                        // Each snapshot carries the reply's cumulative text so far (not just
                        // the newest fragment) — yielding it directly is what lets the reducer
                        // just overwrite the streaming placeholder turn's text as the reply
                        // grows, rather than accumulating chunks itself.
                        for try await snapshot in session.streamResponse(to: request.prompt) {
                            continuation.yield(.chunk(snapshot.content))
                        }
                    } catch {
                        throw .generationFailed(reason: error.localizedDescription)
                    }
                    // A silent Publisher completion dispatches no action on its own (see
                    // `ChatStreamEvent`'s doc) — `.finished` is the explicit "the reply is
                    // complete" signal the reducer actually reacts to.
                    continuation.yield(.finished)
                }
            },
            speak: { text in
                Publisher { continuation throws(SpeechError) in
                    #if os(iOS)
                    do {
                        // Defensively deactivate first — confirmed on a real device that
                        // speaking a reply right after voice input can fail here, because
                        // `startListening`'s `.record` session may still be mid-teardown
                        // (its own deactivation happens asynchronously, once the listening
                        // Subscription actually observes `isListening` go false) when this
                        // tries to switch straight to `.playback` on top of it.
                        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        throw .synthesisFailed(reason: error.localizedDescription)
                    }
                    #endif
                    let synthesizer = AVSpeechSynthesizer()
                    let delegate = SpeechSynthesisDelegate(onFinish: { continuation.finish() })
                    synthesizer.delegate = delegate
                    synthesizer.speak(AVSpeechUtterance(string: text))
                    // Callback-driven (delegate, not async) — park here exactly as
                    // `FileWatcher.swift` does, resuming only on cancellation (mute) or
                    // the delegate's own completion firing `continuation.finish()`.
                    await continuation.suspendUntilCancelled()
                    synthesizer.stopSpeaking(at: .immediate)
                }
            },
            startListening: {
                Publisher { continuation throws(SpeechError) in
                    guard SpeechTranscriber.isAvailable else { throw .recognizerUnavailable }

                    // Both permissions must be explicitly requested *before* the engine ever
                    // touches `inputNode` — touching it first (the previous bug here) implicitly
                    // triggers the OS mic prompt with authorization still undetermined, which
                    // hands back a degenerate 0Hz/0-channel format; `installTap` then traps with
                    // an uncatchable format-validation assertion the instant the app resumes.
                    guard await AVAudioApplication.requestRecordPermission() else {
                        throw .microphoneUnavailable(reason: "Microphone access was denied")
                    }
                    let speechAuthorized = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        SFSpeechRecognizer.requestAuthorization { status in
                            continuation.resume(returning: status == .authorized)
                        }
                    }
                    guard speechAuthorized else { throw .recognizerUnavailable }

                    #if os(iOS)
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        throw .microphoneUnavailable(reason: error.localizedDescription)
                    }
                    #endif

                    // `.volatileResults` is requested explicitly (rather than relying on a
                    // named preset) so finality can be computed precisely below, against
                    // `analyzer.volatileRange`, instead of guessing at what a preset implies.
                    let transcriber = SpeechTranscriber(
                        locale: Locale.current,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: []
                    )

                    // The mic tap is a callback (AVAudioEngine), so buffers are pushed into
                    // our own Subject, never into a bare AsyncStream — `.values` (RC's
                    // Publisher -> AsyncSequence bridge) is used only as an unstored,
                    // same-line argument to satisfy SpeechAnalyzer's foreign initializer.
                    let inputSubject = PassthroughSubject<AnalyzerInput, Never>()
                    let analyzer = SpeechAnalyzer(inputSequence: inputSubject.eraseToPublisher().values, modules: [transcriber])

                    let engine = AVAudioEngine()
                    let inputNode = engine.inputNode
                    let nativeFormat = inputNode.outputFormat(forBus: 0)
                    // Permission is granted by this point, but guard anyway — `installTap`'s
                    // format-validation failure is an uncatchable assertion, not a thrown error.
                    guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
                        throw .microphoneUnavailable(reason: "No valid audio input format is available")
                    }
                    // The hardware's native tap format is 32-bit float (confirmed on a real
                    // device: installing the tap with `nativeFormat` directly crashed inside
                    // `SpeechAnalyzer` with "Audio sample data must be 16-bit signed integers").
                    // `bestAvailableAudioFormat` is the documented way to get the format
                    // `SpeechAnalyzer`/`SpeechTranscriber` actually need.
                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber],
                        considering: nativeFormat
                    ) else {
                        throw .recognizerUnavailable
                    }
                    // `installTap`'s own `format:` parameter can only adapt sample RATE, not the
                    // sample REPRESENTATION — asking it for `analyzerFormat` (Int16) directly,
                    // when the bus's native format is float, also confirmed-crashed on a real
                    // device ("Failed to create tap due to format mismatch"). The tap has to run
                    // in the bus's own native format; an explicit `AVAudioConverter` does the
                    // float → Int16 (and rate) conversion per buffer before handing it off.
                    guard let converter = AVAudioConverter(from: nativeFormat, to: analyzerFormat) else {
                        throw .microphoneUnavailable(reason: "Couldn't create an audio converter for the analyzer's required format")
                    }
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
                        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
                        guard let convertedBuffer = AVAudioPCMBuffer(
                            pcmFormat: analyzerFormat,
                            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                        ) else {
                            return
                        }
                        // Feeds `buffer` to the converter exactly once per `convert()` call —
                        // the standard one-shot pattern for converting a single already-captured
                        // buffer, rather than pulling from a continuous stream. A reference-type
                        // flag (not a captured `var`) because `AVAudioConverterInputBlock` is
                        // `@Sendable` — same reasoning as `SpeechSynthesisDelegate` below.
                        let hasProvidedInput = OneShotFlag()
                        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                            guard !hasProvidedInput.value else {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            hasProvidedInput.value = true
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        var conversionError: NSError?
                        let status = converter.convert(to: convertedBuffer, error: &conversionError, withInputFrom: inputBlock)
                        guard status != .error else {
                            // Previously silent — a buffer that fails to convert just
                            // never reaches the analyzer, with no way to tell why.
                            speechLogger.error("Audio buffer conversion failed: \(conversionError, privacy: .public)")
                            return
                        }
                        inputSubject.send(AnalyzerInput(buffer: convertedBuffer))
                    }

                    do {
                        try engine.start()
                    } catch {
                        speechLogger.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
                        throw .microphoneUnavailable(reason: error.localizedDescription)
                    }
                    speechLogger.debug(
                        "Speech recognition session started (native: \(nativeFormat, privacy: .public), analyzer: \(analyzerFormat, privacy: .public))"
                    )

                    // NOTE: assumes the SpeechTranscriber model asset for `Locale.current` is
                    // already installed. Handling the download flow (`AssetInventory`/
                    // `AssetInstallationRequest`) is a real gap, deliberately left for a
                    // follow-up once this can be tested against a real device.
                    //
                    // `finalizedText` accumulates across multiple `transcriber.results` —
                    // confirmed on a real device that each result covers its OWN time range
                    // rather than extending the previous one, so displaying only the latest
                    // result's own text silently dropped everything said before it (e.g. "Let's
                    // brainstorm about" vanishing once "what an article about monads..."
                    // arrived as the next result). `TranscriptUpdate.text` must always be the
                    // whole utterance so far, per its own doc.
                    let silenceTimer = SilenceTimer()
                    let resultsTask = Task {
                        var finalizedText = ""
                        do {
                            for try await result in transcriber.results {
                                // This result's own range no longer overlaps the analyzer's
                                // volatile (still-revisable) range — safe to commit permanently
                                // rather than re-display as still-changeable.
                                let volatileRange = await analyzer.volatileRange
                                let isSegmentConfirmed = volatileRange.map { result.range.end <= $0.start } ?? true
                                let segmentText = String(result.text.characters)
                                if isSegmentConfirmed {
                                    finalizedText += segmentText
                                }
                                let displayText = isSegmentConfirmed ? finalizedText : finalizedText + segmentText
                                continuation.yield(TranscriptUpdate(text: displayText, isFinal: false))

                                // "The user stopped talking" is a silence timeout, not the
                                // recognizer's own per-segment finality above (which tracks
                                // revision-safety, not speech pauses, and in practice almost
                                // never fires mid-session) — restarted on every new result. A
                                // `let` snapshot (not the loop's mutable `var` directly) since
                                // the restart closure is `@Sendable`.
                                let textSoFar = finalizedText
                                silenceTimer.restart(after: .milliseconds(1500)) {
                                    continuation.yield(TranscriptUpdate(text: textSoFar, isFinal: true))
                                }
                            }
                        } catch {
                            speechLogger.error("Transcriber results stream failed: \(error.localizedDescription, privacy: .public)")
                            continuation.fail(.recognitionFailed(reason: error.localizedDescription))
                        }
                    }

                    await continuation.suspendUntilCancelled()
                    silenceTimer.cancel()
                    resultsTask.cancel()
                    inputNode.removeTap(onBus: 0)
                    engine.stop()
                    try? await analyzer.finalizeAndFinishThroughEndOfInput()
                    speechLogger.debug("Speech recognition session ended")
                }
            },
            loadGitHubSettings: {
                Publisher { continuation in
                    guard
                        let repoURL = UserDefaults.standard.string(forKey: GitHubDefaultsKey.repoURL),
                        let branch = UserDefaults.standard.string(forKey: GitHubDefaultsKey.branch),
                        let token = GitHubTokenKeychain.load()
                    else {
                        continuation.yield(nil)
                        return
                    }
                    continuation.yield(GitHubSettings(repoURL: repoURL, branch: branch, token: token))
                }
            },
            // Only called once, from the link setup screen — verifies the repo/token are
            // actually valid (a live API call) before persisting anything, so a typo'd
            // repo or token surfaces immediately rather than on the first pull/commit.
            linkRepository: { settings in
                Publisher { continuation throws(GitHubError) in
                    guard let repo = settings.repository else { throw .invalidRepoURL }
                    _ = try await GitHubClient.repoInfo(settings, repo: repo)
                    if case .failure(let error) = GitHubTokenKeychain.save(settings.token) {
                        throw error
                    }
                    UserDefaults.standard.set(settings.repoURL, forKey: GitHubDefaultsKey.repoURL)
                    UserDefaults.standard.set(settings.branch, forKey: GitHubDefaultsKey.branch)
                    continuation.yield(())
                }
            },
            // The only field mutable on an already-linked repo — repoURL/token are
            // untouched here, on purpose (see World.updateBranch's doc comment).
            updateBranch: { branch in
                Publisher { continuation throws(GitHubError) in
                    UserDefaults.standard.set(branch, forKey: GitHubDefaultsKey.branch)
                    continuation.yield(())
                }
            },
            unlinkRepository: {
                Publisher { continuation throws(GitHubError) in
                    if case .failure(let error) = GitHubTokenKeychain.delete() {
                        throw error
                    }
                    UserDefaults.standard.removeObject(forKey: GitHubDefaultsKey.repoURL)
                    UserDefaults.standard.removeObject(forKey: GitHubDefaultsKey.branch)
                    continuation.yield(())
                }
            },
            isArticlesDirEmpty: {
                Publisher { continuation in
                    let count = (try? FileManager.default.contentsOfDirectory(at: articlesDir, includingPropertiesForKeys: nil)
                        .filter { $0.pathExtension == "json" }.count) ?? 0
                    continuation.yield(count == 0)
                }
            },
            previewPull: { settings in
                Publisher { continuation throws(GitHubError) in
                    guard let repo = settings.repository else { throw .invalidRepoURL }
                    let entries = try await GitHubClient.listArticles(settings, repo: repo)
                    var toAdd: [PullPreview.FileChange] = []
                    var toUpdate: [PullPreview.FileChange] = []
                    for entry in entries where entry.type == "file" && entry.name.hasSuffix(".json") {
                        guard let downloadURL = entry.downloadURL else { continue }
                        let remoteData = try await GitHubClient.downloadRaw(downloadURL)
                        let localURL = articlesDir.appendingPathComponent(entry.name)
                        if let localData = try? Data(contentsOf: localURL) {
                            if localData != remoteData {
                                toUpdate.append(PullPreview.FileChange(name: entry.name, content: remoteData))
                            }
                        } else {
                            toAdd.append(PullPreview.FileChange(name: entry.name, content: remoteData))
                        }
                    }
                    continuation.yield(PullPreview(toAdd: toAdd, toUpdate: toUpdate, localOnlyChanges: toUpdate.map(\.name)))
                }
            },
            applyPull: { preview in
                Publisher { continuation throws(GitHubError) in
                    var count = 0
                    for change in preview.toAdd + preview.toUpdate {
                        let url = articlesDir.appendingPathComponent(change.name)
                        do {
                            try change.content.write(to: url, options: .atomic)
                            count += 1
                        } catch {
                            throw .network(error.localizedDescription)
                        }
                    }
                    continuation.yield(count)
                }
            },
            commitLocalChanges: { settings in
                Publisher { continuation throws(GitHubError) in
                    guard let repo = settings.repository else { throw .invalidRepoURL }

                    let localFiles: [URL]
                    do {
                        localFiles = try FileManager.default.contentsOfDirectory(at: articlesDir, includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension == "json" }
                    } catch {
                        throw .network(error.localizedDescription)
                    }

                    var dirty: [(name: String, content: Data)] = []
                    for file in localFiles {
                        guard let localData = try? Data(contentsOf: file) else { continue }
                        let name = file.lastPathComponent
                        let remoteData = try await GitHubClient.fileContent(settings, repo: repo, path: "Articles/\(name)")
                        if remoteData != localData {
                            dirty.append((name: name, content: localData))
                        }
                    }

                    guard !dirty.isEmpty else {
                        continuation.yield(.nothingToCommit)
                        return
                    }

                    // Ensure the branch exists, creating it from the default branch's tip
                    // if this is a brand-new branch name.
                    var tipSHA = try await GitHubClient.branchTipSHA(settings, repo: repo, branch: settings.branch)
                    if tipSHA == nil {
                        let info = try await GitHubClient.repoInfo(settings, repo: repo)
                        guard let defaultTip = try await GitHubClient.branchTipSHA(settings, repo: repo, branch: info.defaultBranch)
                        else {
                            throw .badStatus(404)
                        }
                        try await GitHubClient.createBranch(settings, repo: repo, branch: settings.branch, atSHA: defaultTip)
                        tipSHA = defaultTip
                    }
                    guard let parentSHA = tipSHA else { throw .badStatus(404) }

                    let baseTreeSHA = try await GitHubClient.baseTreeSHA(settings, repo: repo, commitSHA: parentSHA)

                    var treeEntries: [(path: String, blobSHA: String)] = []
                    for file in dirty {
                        let blobSHA = try await GitHubClient.createBlob(settings, repo: repo, content: file.content)
                        treeEntries.append((path: "Articles/\(file.name)", blobSHA: blobSHA))
                    }

                    let newTreeSHA = try await GitHubClient.createTree(
                        settings,
                        repo: repo,
                        baseTreeSHA: baseTreeSHA,
                        entries: treeEntries
                    )
                    let message = "Update \(dirty.count) article\(dirty.count == 1 ? "" : "s") from Article Editor"
                    let newCommitSHA = try await GitHubClient.createCommit(
                        settings,
                        repo: repo,
                        message: message,
                        treeSHA: newTreeSHA,
                        parentSHA: parentSHA
                    )
                    try await GitHubClient.updateBranchRef(settings, repo: repo, branch: settings.branch, toSHA: newCommitSHA)

                    guard let commitURL = URL(string: "https://github.com/\(repo.owner)/\(repo.name)/commit/\(newCommitSHA)") else {
                        throw .invalidRepoURL
                    }
                    continuation.yield(.committed(files: dirty.map(\.name), commitURL: commitURL))
                }
            },
            openPullRequest: { settings in
                Publisher { continuation throws(GitHubError) in
                    guard let repo = settings.repository else { throw .invalidRepoURL }
                    if let existing = try await GitHubClient.existingPullRequest(settings, repo: repo, branch: settings.branch) {
                        continuation.yield(existing.htmlURL)
                        return
                    }
                    let info = try await GitHubClient.repoInfo(settings, repo: repo)
                    let pr = try await GitHubClient.createPullRequest(
                        settings,
                        repo: repo,
                        base: info.defaultBranch,
                        title: "Article updates",
                        body: "Opened from the Article Editor app."
                    )
                    continuation.yield(pr.htmlURL)
                }
            }
        )
    }()
}

/// Non-secret GitHub sync settings (repo URL, branch) — UserDefaults, same convention
/// PookiePayslip's AppSettings.swift uses. The token itself never lands here, only in
/// GitHubTokenKeychain — see World.linkRepository/updateBranch/unlinkRepository.
private enum GitHubDefaultsKey {
    static let repoURL = "io.lu.ArticleEditor.github.repoURL"
    static let branch = "io.lu.ArticleEditor.github.branch"
}

private func sha256Hex(of data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// A single mutable `Bool`, boxed in a reference type so it can be mutated from inside a
/// `@Sendable` closure (`AVAudioConverterInputBlock`). `@unchecked Sendable` is safe here:
/// exactly one closure ever touches a given instance, and only within the single,
/// synchronous `converter.convert(...)` call that instance was created for.
/// Structured, low-overhead logging (`os.Logger`) for the speech-recognition pipeline —
/// deliberately NOT a dispatched `Action`/`AppState` field. High-frequency mechanical
/// events (session start/stop, a buffer conversion failing) have no identity or meaning
/// beyond this one boundary call; routing them through the Store would either flood the
/// action/time-travel history with noise or put dispatch overhead on the audio thread's
/// real-time callback. This is a decoupled diagnostic channel, same category as Console/
/// Instruments — separate from the Redux state that drives the UI.
private let speechLogger = Logger(subsystem: "io.lu.ArticleEditor", category: "SpeechRecognition")

private final class OneShotFlag: @unchecked Sendable {
    var value = false
}

/// A restartable, cancellable delayed action — debounces "the user stopped talking" out of
/// a continuous stream of transcript results. `@unchecked Sendable` is safe here: `restart`/
/// `cancel` are only ever called sequentially from the single `resultsTask` loop (never
/// concurrently with each other), and the only cross-task hop is the previous `Task`'s own
/// cancellation, which is inherently safe.
private final class SilenceTimer: @unchecked Sendable {
    private var task: Task<Void, Never>?

    func restart(after duration: Duration, action: @escaping @Sendable () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
    }
}

/// Bridges `AVSpeechSynthesizerDelegate`'s callback-based completion to `World.speak`'s
/// `Publisher`. `@unchecked Sendable` is safe here: the only stored state is an immutable
/// `@Sendable` closure, and `AVSpeechSynthesizerDelegate` (an Objective-C protocol) isn't
/// itself `Sendable`-checkable by the compiler.
private final class SpeechSynthesisDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
