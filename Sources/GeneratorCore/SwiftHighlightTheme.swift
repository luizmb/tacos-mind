/// The "Luba" Xcode theme colors code blocks render with, as hex strings — kept as the
/// single source of truth an editor can read directly, rather than a Apple-UI-only `Color`/
/// `NSColor`/`UIColor` (this target ships on Linux/Windows/Android too, so it can't import
/// AppKit/UIKit). Keep in sync with the `.token-*`/`pre` rules in `Stylesheet.swift` — they
/// aren't generated from this table (the stylesheet is a plain string literal), so a color
/// changed in one place must be changed in the other.
public enum SwiftHighlightTheme {
    /// `pre { background: … }` — fixed regardless of the site's light/dark toggle: code
    /// blocks are a dark "editor island" on purpose (see the comment above `pre` in
    /// `Stylesheet.swift`).
    public static let backgroundHex = "#1e2028"
    /// `pre { color: … }` — the base/default text color for unstyled tokens (punctuation,
    /// anything `swiftHighlightTokens(in:)` doesn't classify).
    public static let foregroundHex = "#ffffff"

    /// `token-*` category name → hex color, matching `Stylesheet.swift`'s `.token-*` rules.
    public static let colorsByCategory: [String: String] = [
        "keyword": "#ffe400",
        "string": "#ff2700",
        "regex": "#ff2700",
        "number": "#ff00e3",
        "comment": "#16ff00",
        "comment-doc": "#17bf06",
        "mark": "#92a1b1",
        "attribute": "#22fef0",
        "declaration-type": "#5dd8ff",
        "declaration-other": "#41a1c0",
        "type": "#3ea58f",
        "variable": "#65dcf3",
        "function-call": "#3f90cf",
        "constant": "#00ffc1",
        "macro": "#e58800",
        "preprocessor": "#ff8f04",
    ]
}
