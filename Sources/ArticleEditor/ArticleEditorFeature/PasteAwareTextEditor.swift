import AppDomain
import CoreText
import Foundation
import GeneratorCore
import SwiftUI

/// Registers the site's own bundled JetBrains Mono files so "JetBrainsMono-Regular"
/// resolves via `NSFont`/`UIFont` — done once per process, lazily, the first time a
/// code block is rendered.
private let registerJetBrainsMono: Bool = {
    var registeredAny = false
    for url in jetBrainsMonoFontURLs() where CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
        registeredAny = true
    }
    return registeredAny
}()

/// Parses a `"#rrggbb"` (or `"rrggbb"`) string into its packed `0xRRGGBB` value.
private func hexValue(_ hex: String) -> UInt64 {
    var hexString = hex
    if hexString.hasPrefix("#") { hexString.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: hexString).scanHexInt64(&value)
    return value
}

#if os(macOS)
import AppKit

/// JetBrains Mono (the site's own code-block font) with contextual alternates enabled
/// — the same effect as the site's CSS `font-variant-ligatures: contextual`. Falls back
/// to the system monospace font if registration didn't take (can't be visually
/// confirmed from here — verify ligatures render on a real build).
private func codeFont(size: CGFloat) -> NSFont {
    _ = registerJetBrainsMono
    guard let base = NSFont(name: "JetBrainsMono-Regular", size: size) else {
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    let descriptor = base.fontDescriptor.addingAttributes([
        NSFontDescriptor.AttributeName.featureSettings: [
            [
                NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kContextualLigaturesOnSelector
            ]
        ]
    ])
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// A named site font (Avenir-Book for body, Avenir-Heavy for headings, …) — falls back to
/// the system font if, somehow, it's unavailable (Avenir ships with macOS, so this is a
/// defensive floor, not an expected path).
private func siteFont(name: String, size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

private func color(hex: String) -> NSColor {
    let value = hexValue(hex)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// A plain-text multi-line editor that intercepts paste: pasting a URL over a text
/// selection replaces the selection with a `[selected text](url)` markdown link (the
/// exact syntax the site's own `InlineMarkup.swift` parses) instead of dropping the raw
/// URL in place. Every other paste falls through to the platform's normal behaviour.
/// Only applies to plain-text (`isMonospace == false`, i.e. paragraph) blocks — code
/// doesn't get markdown links, so it keeps the platform's ordinary paste/menu behaviour.
///
/// For paragraph blocks it also replaces the standard right-click menu with a link-aware
/// one: selecting text offers "Link to Article" / "Link to Web…" / "Paste Link"; placing
/// the caret inside an existing link (no selection) offers "Edit Link" (re-target,
/// change URL, or remove).
public struct PasteAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isMonospace: Bool
    var isSyntaxHighlighted: Bool
    var fontName: String
    var fontSize: CGFloat
    var allSummaries: [ArticleSummary]
    var disablesNewlines: Bool
    var isLinkAware: Bool

    public init(
        text: Binding<String>,
        isMonospace: Bool = false,
        isSyntaxHighlighted: Bool = false,
        fontName: String = SiteTypography.bodyFontName,
        fontSize: CGFloat = SiteTypography.bodySize,
        allSummaries: [ArticleSummary] = [],
        disablesNewlines: Bool = false,
        isLinkAware: Bool = true
    ) {
        _text = text
        self.isMonospace = isMonospace
        self.isSyntaxHighlighted = isSyntaxHighlighted
        self.fontName = fontName
        self.fontSize = fontSize
        self.allSummaries = allSummaries
        self.disablesNewlines = disablesNewlines
        self.isLinkAware = isLinkAware
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = LinkPastingNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = isMonospace ? codeFont(size: fontSize) : siteFont(name: fontName, size: fontSize)
        textView.string = text
        textView.allSummaries = allSummaries
        textView.disablesNewlines = disablesNewlines
        textView.isLinkAware = isLinkAware
        textView.isMonospace = isMonospace
        textView.isSyntaxHighlighted = isSyntaxHighlighted
        textView.isEditable = true
        textView.isSelectable = true
        // The app has its own document-level undo/redo (checkpoints, debounced text
        // edits) driven by Cmd+Z/Shift+Cmd+Z at the toolbar — NSTextView's own built-in
        // per-keystroke undo would otherwise compete for the same shortcut whenever a
        // text field has focus, giving inconsistent behavior depending on where the
        // cursor happens to be.
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.drawsBackground = true
        // Syntax-highlighted (code) blocks are a fixed dark "editor island" regardless of
        // the app's own light/dark mode, matching the site's own `pre { background: … }`
        // — see `SwiftHighlightTheme`/`Stylesheet.swift`. Every other field — including
        // plain monospace ones like Brainstorming — uses the adaptive system background.
        textView.backgroundColor = isSyntaxHighlighted ? color(hex: SwiftHighlightTheme.backgroundHex) : .textBackgroundColor
        textView.recolorSwiftCode()
        return textView
    }

    public func updateNSView(_ view: NSTextView, context: Context) {
        guard let textView = view as? LinkPastingNSTextView else { return }
        textView.allSummaries = allSummaries
        textView.disablesNewlines = disablesNewlines
        textView.isLinkAware = isLinkAware
        textView.isMonospace = isMonospace
        textView.isSyntaxHighlighted = isSyntaxHighlighted
        textView.font = isMonospace ? codeFont(size: fontSize) : siteFont(name: fontName, size: fontSize)
        guard textView.string != text else { return }
        textView.string = text
        // Setting `.string` directly (as opposed to the user typing) never triggers
        // `didChangeText()`, so the cached intrinsic height from whatever the PREVIOUS
        // article's content was would otherwise stick around — e.g. switching to an
        // article with an empty Brainstorming field kept the previous one's multi-line
        // height. Matches the iOS side, which already does this in `updateUIView`.
        textView.invalidateIntrinsicContentSize()
        textView.recolorSwiftCode()
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareTextEditor
        init(_ parent: PasteAwareTextEditor) { self.parent = parent }
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class LinkPastingNSTextView: NSTextView {
    var allSummaries: [ArticleSummary] = []
    var disablesNewlines = false
    var isLinkAware = true
    var isMonospace = false
    var isSyntaxHighlighted = false

    /// Grows with content instead of scrolling: no enclosing `NSScrollView`, so the
    /// surrounding `Form`/`Section` scrolls the whole page and this box just gets taller.
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return NSSize(width: NSView.noIntrinsicMetric, height: usedHeight + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        recolorSwiftCode()
    }

    /// Colors code blocks exactly like the generated site (`swiftHighlightTokens`, the same
    /// SwiftSyntax-based classifier `highlightSwift` uses to render the HTML version).
    /// Recoloring only ever changes attributes on the existing `textStorage` — never the
    /// string content — so `selectedRange` (the caret/selection) is left untouched by
    /// AppKit: attribute-only edits don't invalidate it the way a character edit would.
    /// That's what keeps typing, pasting, and selecting from ever jumping the cursor.
    func recolorSwiftCode() {
        guard isSyntaxHighlighted, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: color(hex: SwiftHighlightTheme.foregroundHex), range: fullRange)
        for token in swiftHighlightTokens(in: textStorage.string) {
            guard let hex = SwiftHighlightTheme.colorsByCategory[token.category] else { continue }
            textStorage.addAttribute(.foregroundColor, value: color(hex: hex), range: token.range)
        }
        textStorage.endEditing()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if oldWidth != newSize.width {
            invalidateIntrinsicContentSize()
        }
    }

    /// Paragraph blocks aren't `<br />`-capable on the site (a paragraph is one
    /// continuous string, word-wrapped only at print time), so a literal Return would
    /// just silently corrupt the round-trip. Code blocks set `disablesNewlines = false`.
    override func insertNewline(_ sender: Any?) {
        guard !disablesNewlines else { return }
        super.insertNewline(sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard
            isLinkAware,
            selectedRange().length > 0,
            let urlString = pastedURLString(from: pasteboard),
            let selectedText = (string as NSString?)?.substring(with: selectedRange())
        else {
            super.paste(sender)
            return
        }
        insertText("[\(selectedText)](\(urlString))", replacementRange: selectedRange())
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isLinkAware else { return super.menu(for: event) }
        let menu = super.menu(for: event) ?? NSMenu()
        let selection = selectedRange()
        if selection.length > 0 {
            insertSelectionLinkItems(into: menu, over: selection)
        } else if let link = detectLink(in: string, at: selection.location) {
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(makeEditLinkItem(for: link), at: 0)
        }
        return menu
    }

    private func insertSelectionLinkItems(into menu: NSMenu, over selection: NSRange) {
        menu.insertItem(.separator(), at: 0)
        if let pasteURL = pastedURLString(from: .general) {
            menu.insertItem(ClosureMenuItem(title: "Paste Link") { [weak self] in
                self?.applyLink(externalURL: pasteURL, over: selection)
            }, at: 0)
        }
        menu.insertItem(ClosureMenuItem(title: "Link to Web…") { [weak self] in
            self?.presentWebLinkPrompt(initialURL: "") { url in self?.applyLink(externalURL: url, over: selection) }
        }, at: 0)
        let articleItem = NSMenuItem(title: "Link to Article", action: nil, keyEquivalent: "")
        let articleSubmenu = NSMenu()
        articleSubmenu.items = makeArticleItems { [weak self] slug in self?.applyLink(slug: slug, over: selection) }
        articleItem.submenu = articleSubmenu
        menu.insertItem(articleItem, at: 0)
    }

    private func makeArticleItems(onSelect: @escaping (String) -> Void) -> [NSMenuItem] {
        allSummaries.map { summary in
            ClosureMenuItem(title: "#\(summary.number) — \(summary.title)") { onSelect(summary.slug) }
        }
    }

    private func makeEditLinkItem(for link: DetectedLink) -> NSMenuItem {
        let parentItem = NSMenuItem(title: "Edit Link", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        switch link.kind {
        case .internalSlug:
            submenu.items = makeArticleItems { [weak self] slug in self?.replaceLink(link, withSlug: slug) } + [.separator()]
        case .external(let url, _):
            submenu.items = [
                ClosureMenuItem(title: "Change URL…") { [weak self] in
                    self?.presentWebLinkPrompt(initialURL: url) { newURL in self?.replaceLink(link, withURL: newURL) }
                },
                .separator()
            ]
        }
        submenu.addItem(ClosureMenuItem(title: "Remove Link") { [weak self] in self?.removeLink(link) })
        parentItem.submenu = submenu
        return parentItem
    }

    func applyLink(slug: String, over range: NSRange) {
        let displayText = (string as NSString).substring(with: range)
        insertText(internalLinkText(displayText: displayText, slug: slug), replacementRange: range)
    }

    func applyLink(externalURL url: String, over range: NSRange) {
        let displayText = (string as NSString).substring(with: range)
        insertText(externalLinkText(displayText: displayText, url: url), replacementRange: range)
    }

    func replaceLink(_ link: DetectedLink, withSlug slug: String) {
        insertText(internalLinkText(displayText: link.kind.displayText, slug: slug), replacementRange: link.range)
    }

    func replaceLink(_ link: DetectedLink, withURL url: String) {
        insertText(externalLinkText(displayText: link.kind.displayText, url: url), replacementRange: link.range)
    }

    func removeLink(_ link: DetectedLink) {
        insertText(link.kind.displayText, replacementRange: link.range)
    }

    func presentWebLinkPrompt(initialURL: String, completion: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Link to Web"
        alert.informativeText = "Enter the URL"
        let field = NSTextField(string: initialURL)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            completion(url)
        }
    }
}

/// An `NSMenuItem` that runs a closure instead of target/action selectors — every custom
/// item in the link-editing menus is built this way.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}

private func pastedURLString(from pasteboard: NSPasteboard) -> String? {
    if let urlString = pasteboard.string(forType: .URL) { return urlString }
    guard let plain = pasteboard.string(forType: .string), isHTTPURL(plain) else { return nil }
    return plain
}

#else
import UIKit

/// JetBrains Mono (the site's own code-block font) with contextual alternates enabled
/// — the same effect as the site's CSS `font-variant-ligatures: contextual`. Falls back
/// to the system monospace font if registration didn't take (can't be visually
/// confirmed from here — verify ligatures render on a real build).
private func codeFont(size: CGFloat) -> UIFont {
    _ = registerJetBrainsMono
    guard let base = UIFont(name: "JetBrainsMono-Regular", size: size) else {
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    let descriptor = base.fontDescriptor.addingAttributes([
        UIFontDescriptor.AttributeName.featureSettings: [
            [
                UIFontDescriptor.FeatureKey.type: kLigaturesType,
                UIFontDescriptor.FeatureKey.selector: kContextualLigaturesOnSelector
            ]
        ]
    ])
    return UIFont(descriptor: descriptor, size: size)
}

/// A named site font (Avenir-Book for body, Avenir-Heavy for headings, …) — falls back to
/// the system font if, somehow, it's unavailable (Avenir ships with iOS, so this is a
/// defensive floor, not an expected path).
private func siteFont(name: String, size: CGFloat) -> UIFont {
    UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

private func color(hex: String) -> UIColor {
    let value = hexValue(hex)
    return UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// Only applies to plain-text (`isMonospace == false`, i.e. paragraph) blocks — code
/// doesn't get markdown links, so it keeps the platform's ordinary paste/menu behaviour.
///
/// For paragraph blocks it also augments the system edit menu (the popup that appears on
/// text selection) with link-aware items: selecting text offers "Link to Article" /
/// "Link to Web…" / "Paste Link"; placing the caret inside an existing link (no
/// selection) offers "Edit Link" (re-target, change URL, or remove).
public struct PasteAwareTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isMonospace: Bool
    var isSyntaxHighlighted: Bool
    var fontName: String
    var fontSize: CGFloat
    var allSummaries: [ArticleSummary]
    var disablesNewlines: Bool
    var isLinkAware: Bool

    public init(
        text: Binding<String>,
        isMonospace: Bool = false,
        isSyntaxHighlighted: Bool = false,
        fontName: String = SiteTypography.bodyFontName,
        fontSize: CGFloat = SiteTypography.bodySize,
        allSummaries: [ArticleSummary] = [],
        disablesNewlines: Bool = false,
        isLinkAware: Bool = true
    ) {
        _text = text
        self.isMonospace = isMonospace
        self.isSyntaxHighlighted = isSyntaxHighlighted
        self.fontName = fontName
        self.fontSize = fontSize
        self.allSummaries = allSummaries
        self.disablesNewlines = disablesNewlines
        self.isLinkAware = isLinkAware
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = LinkPastingUITextView()
        textView.delegate = context.coordinator
        textView.font = isMonospace ? codeFont(size: fontSize) : siteFont(name: fontName, size: fontSize)
        textView.text = text
        textView.disablesNewlines = disablesNewlines
        textView.isLinkAware = isLinkAware
        textView.isMonospace = isMonospace
        textView.isSyntaxHighlighted = isSyntaxHighlighted
        // Grows with content instead of scrolling: no internal scrolling, so the
        // surrounding Form scrolls the whole page and this box just gets taller.
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        // Syntax-highlighted (code) blocks are a fixed dark "editor island" regardless of
        // the app's own light/dark mode, matching the site's own `pre { background: … }`
        // — see `SwiftHighlightTheme`/`Stylesheet.swift`. Every other field — including
        // plain monospace ones like Brainstorming — uses the adaptive system background.
        textView.backgroundColor = isSyntaxHighlighted ? color(hex: SwiftHighlightTheme.backgroundHex) : .secondarySystemBackground
        textView.recolorSwiftCode()
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        guard let textView = uiView as? LinkPastingUITextView else { return }
        textView.disablesNewlines = disablesNewlines
        textView.isLinkAware = isLinkAware
        textView.isMonospace = isMonospace
        textView.isSyntaxHighlighted = isSyntaxHighlighted
        textView.font = isMonospace ? codeFont(size: fontSize) : siteFont(name: fontName, size: fontSize)
        guard textView.text != text else { return }
        textView.text = text
        textView.invalidateIntrinsicContentSize()
        textView.recolorSwiftCode()
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteAwareTextEditor
        init(_ parent: PasteAwareTextEditor) { self.parent = parent }

        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
            (textView as? LinkPastingUITextView)?.recolorSwiftCode()
        }

        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let linkTextView = textView as? LinkPastingUITextView, linkTextView.disablesNewlines else { return true }
            return !text.contains("\n")
        }

        public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let linkTextView = textView as? LinkPastingUITextView, linkTextView.isLinkAware else {
                return UIMenu(children: suggestedActions)
            }
            let text = textView.text ?? ""

            if range.length > 0 {
                var items: [UIMenuElement] = []
                let articleActions = parent.allSummaries.map { summary in
                    UIAction(title: "#\(summary.number) — \(summary.title)") { _ in
                        linkTextView.applyLink(slug: summary.slug, over: range)
                    }
                }
                items.append(UIMenu(title: "Link to Article", children: articleActions))
                items.append(UIAction(title: "Link to Web…") { _ in
                    linkTextView.presentWebLinkPrompt(initialURL: "") { url in linkTextView.applyLink(externalURL: url, over: range) }
                })
                if let pasteURL = pastedURLString(from: .general) {
                    items.append(UIAction(title: "Paste Link") { _ in linkTextView.applyLink(externalURL: pasteURL, over: range) })
                }
                return UIMenu(children: items + [UIMenu(options: .displayInline, children: suggestedActions)])
            }

            guard let link = detectLink(in: text, at: range.location) else { return UIMenu(children: suggestedActions) }
            let editMenu: UIMenu
            switch link.kind {
            case .internalSlug:
                let articleActions = parent.allSummaries.map { summary in
                    UIAction(title: "#\(summary.number) — \(summary.title)") { _ in linkTextView.replaceLink(link, withSlug: summary.slug) }
                }
                editMenu = UIMenu(title: "Edit Link", children: [
                    UIMenu(options: .displayInline, children: articleActions),
                    UIAction(title: "Remove Link", attributes: .destructive) { _ in linkTextView.removeLink(link) }
                ])
            case .external(let url, _):
                editMenu = UIMenu(title: "Edit Link", children: [
                    UIAction(title: "Change URL…") { _ in
                        linkTextView.presentWebLinkPrompt(initialURL: url) { newURL in linkTextView.replaceLink(link, withURL: newURL) }
                    },
                    UIAction(title: "Remove Link", attributes: .destructive) { _ in linkTextView.removeLink(link) }
                ])
            }
            return UIMenu(children: [editMenu, UIMenu(options: .displayInline, children: suggestedActions)])
        }
    }
}

private final class LinkPastingUITextView: UITextView {
    var disablesNewlines = false
    var isLinkAware = true
    var isMonospace = false
    var isSyntaxHighlighted = false

    // Same reasoning as `LinkPastingNSTextView.allowsUndo = false` — the app's own
    // document-level undo/redo (Cmd+Z/Shift+Cmd+Z at the toolbar) is the only undo
    // system; UIKit's own per-keystroke undo would otherwise compete for it.
    override var undoManager: UndoManager? { nil }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else { return super.intrinsicContentSize }
        let fitting = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }

    /// Colors code blocks exactly like the generated site (`swiftHighlightTokens`, the same
    /// SwiftSyntax-based classifier `highlightSwift` uses to render the HTML version).
    /// Recoloring only ever changes attributes on the existing `textStorage` — never the
    /// string content — so the selection/caret is left untouched by UIKit: attribute-only
    /// edits don't invalidate it the way a character edit would. That's what keeps typing,
    /// pasting, and selecting from ever jumping the cursor.
    func recolorSwiftCode() {
        guard isSyntaxHighlighted else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: color(hex: SwiftHighlightTheme.foregroundHex), range: fullRange)
        for token in swiftHighlightTokens(in: textStorage.string) {
            guard let hex = SwiftHighlightTheme.colorsByCategory[token.category] else { continue }
            textStorage.addAttribute(.foregroundColor, value: color(hex: hex), range: token.range)
        }
        textStorage.endEditing()
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        guard
            isLinkAware,
            let range = selectedTextRange, !range.isEmpty,
            let urlString = pastedURLString(from: pasteboard),
            let selectedText = text(in: range)
        else {
            super.paste(sender)
            return
        }
        replace(range, withText: "[\(selectedText)](\(urlString))")
    }

    func applyLink(slug: String, over range: NSRange) {
        guard let uiRange = textRange(forNSRange: range), let displayText = text(in: uiRange) else { return }
        replace(uiRange, withText: internalLinkText(displayText: displayText, slug: slug))
    }

    func applyLink(externalURL url: String, over range: NSRange) {
        guard let uiRange = textRange(forNSRange: range), let displayText = text(in: uiRange) else { return }
        replace(uiRange, withText: externalLinkText(displayText: displayText, url: url))
    }

    func replaceLink(_ link: DetectedLink, withSlug slug: String) {
        guard let uiRange = textRange(forNSRange: link.range) else { return }
        replace(uiRange, withText: internalLinkText(displayText: link.kind.displayText, slug: slug))
    }

    func replaceLink(_ link: DetectedLink, withURL url: String) {
        guard let uiRange = textRange(forNSRange: link.range) else { return }
        replace(uiRange, withText: externalLinkText(displayText: link.kind.displayText, url: url))
    }

    func removeLink(_ link: DetectedLink) {
        guard let uiRange = textRange(forNSRange: link.range) else { return }
        replace(uiRange, withText: link.kind.displayText)
    }

    func presentWebLinkPrompt(initialURL: String, completion: @escaping (String) -> Void) {
        guard let presenter = nearestViewController else { return }
        let alert = UIAlertController(title: "Link to Web", message: "Enter the URL", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initialURL
            field.placeholder = "https://…"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            let url = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            completion(url)
        })
        presenter.present(alert, animated: true)
    }

    private func textRange(forNSRange nsRange: NSRange) -> UITextRange? {
        guard
            let start = position(from: beginningOfDocument, offset: nsRange.location),
            let end = position(from: start, offset: nsRange.length)
        else { return nil }
        return textRange(from: start, to: end)
    }
}

private extension UIResponder {
    var nearestViewController: UIViewController? {
        (self as? UIViewController) ?? next?.nearestViewController
    }
}

private func pastedURLString(from pasteboard: UIPasteboard) -> String? {
    if let url = pasteboard.url { return url.absoluteString }
    guard let plain = pasteboard.string, isHTTPURL(plain) else { return nil }
    return plain
}
#endif

private func isHTTPURL(_ string: String) -> Bool {
    guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return url.scheme == "http" || url.scheme == "https"
}
