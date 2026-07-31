import GeneratorCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Mirrors the generated site's own typography (`GeneratorCore/Stylesheet.swift`) so a
/// block edited here reads close to how it will actually render: headings look like
/// headings, paragraphs like paragraphs. Avenir ships with macOS/iOS — the stylesheet's
/// own comment notes it's referenced by name rather than embedded for exactly that
/// reason — so no bundling/registration is needed, unlike JetBrains Mono.
public enum SiteTypography {
    public static let bodyFontName = "Avenir-Book"
    public static let headingFontName = "Avenir-Heavy"

    /// `h1` (the article title) — no dedicated rule in the stylesheet, so it renders at the
    /// browser's UA default for `h1` (`2em`, i.e. 32pt at the site's unmodified 16px root).
    public static let titleSize: CGFloat = 32
    /// `h2` — `font-size: 1.5rem` (24pt at the site's unmodified 16px root).
    public static let sectionHeadingSize: CGFloat = 24
    /// `h3` — `font-size: 1.1875rem` (19pt).
    public static let subsectionHeadingSize: CGFloat = 19
    /// `body`/`p`/`li` — default `1rem` (16pt).
    public static let bodySize: CGFloat = 16
    /// `figcaption` — `font-size: 0.875rem` (14pt).
    public static let captionSize: CGFloat = 14
    /// `code` — `font-size: 0.875em` of the 16pt body (14pt).
    public static let codeSize: CGFloat = 14

    public static func heading(level: HeadingLevel) -> Font {
        .custom(headingFontName, size: level == .section ? sectionHeadingSize : subsectionHeadingSize)
    }

    public static let title = Font.custom(headingFontName, size: titleSize)
    public static let body = Font.custom(bodyFontName, size: bodySize)
    public static let caption = Font.custom(bodyFontName, size: captionSize)
}

extension Color {
    /// The same background `PasteAwareTextEditor`'s `NSTextView`/`UITextView` renders
    /// against, applied explicitly here (and set explicitly on the text views themselves,
    /// not left to each platform's differing implicit default) so every block's editor —
    /// plain `TextField` or not — looks like one consistent surface.
    static var textEditorBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
