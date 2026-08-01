public let siteStylesheet = """
@font-face {
  font-family: "JetBrains Mono";
  src: url("fonts/JetBrainsMono-Regular.ttf") format("truetype");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}

@font-face {
  font-family: "JetBrains Mono";
  src: url("fonts/JetBrainsMono-Bold.ttf") format("truetype");
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}

@font-face {
  font-family: "JetBrains Mono";
  src: url("fonts/JetBrainsMono-Italic.ttf") format("truetype");
  font-weight: 400;
  font-style: italic;
  font-display: swap;
}

:root {
  color-scheme: light dark;
  --bg: #ffffff;
  --fg: #1a1a1a;
  --muted: #6b7280;
  --code-bg: #f4f4f5;
  --code-border: #e4e4e7;
  --inline-code-bg: #fbeae8;
  --inline-code-fg: #b5433d;
  --link: #0b63ce;
  --link-hover: #084b9e;
  --mono: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #14161a;
    --fg: #e4e4e7;
    --muted: #9ca3af;
    --code-bg: #1e2126;
    --code-border: #2c2f36;
    --inline-code-bg: #292927;
    --inline-code-fg: #da615c;
    --link: #58a6ff;
    --link-hover: #85c0ff;
  }
}

* {
  box-sizing: border-box;
}

/*
 * Avenir is referenced by name only, deliberately not embedded: it's a Linotype/Heidelberger
 * trademark bundled with macOS under Apple's system-font license, which doesn't grant
 * redistribution rights. Visitors on Apple platforms (the expected majority for Swift/FP
 * content) get the real thing for free since it's already on their device; everyone else
 * falls through to the system sans stack.
 */
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: Avenir, "Avenir Next", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.6;
}

header {
  border-bottom: 1px solid var(--code-border);
}

header nav {
  max-width: 42rem;
  margin: 0 auto;
  padding: 1.25rem;
}

header nav a {
  color: var(--fg);
  text-decoration: none;
  font-weight: 700;
  letter-spacing: 0.02em;
}

header .tag-strip {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.75rem;
}

main.article {
  max-width: 42rem;
  margin: 0 auto;
  padding: 3rem 1.25rem;
}

/*
 * Links are deliberately loud — accent color, solid underline, a touch bolder — so they can
 * never be mistaken for body text. Visited links keep the exact same color on purpose: on a
 * reference site, "have I clicked this before" is noise, not signal.
 */
main.article a,
main.article a:visited {
  color: var(--link);
  font-weight: 600;
  text-decoration: underline;
  text-decoration-thickness: 1.5px;
  text-underline-offset: 0.2em;
}

main.article a:hover {
  color: var(--link-hover);
  text-decoration-thickness: 2.5px;
}

h1, h2, h3 {
  line-height: 1.25;
  margin: 0 0 0.75em;
}

.article-meta {
  color: var(--muted);
  font-size: 0.875rem;
  margin-bottom: 0.75rem;
}

.article-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 2.5rem;
}

/*
 * Tag chips appear in the header strip and under article titles. They are links, but
 * deliberately quiet ones — the main.article "loud link" rule must not win here, hence
 * the extra-specific selectors.
 */
a.tag,
a.tag:visited,
main.article a.tag,
main.article a.tag:visited {
  font-family: var(--mono);
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--muted);
  background: var(--code-bg);
  border: 1px solid var(--code-border);
  border-radius: 0.25rem;
  padding: 0.15em 0.5em;
  text-decoration: none;
}

a.tag:hover,
main.article a.tag:hover {
  color: var(--link);
  border-color: var(--link);
}

h2 {
  margin-top: 2em;
  font-size: 1.5rem;
}

h3 {
  margin-top: 1.75em;
  font-size: 1.1875rem;
}

p {
  margin: 0 0 1.25em;
}

li {
  margin-bottom: 0.75rem;
}

.article-index {
  list-style: none;
  margin: 0;
  padding: 0;
}

img, video {
  max-width: 100%;
  height: auto;
  border-radius: 0.5rem;
}

.equation {
  margin: 1.75rem 0;
  padding: 1.25rem 1rem;
  background: var(--code-bg);
  border-radius: 0.5rem;
  overflow-x: auto;
  text-align: center;
}

.equation math {
  font-size: 1.25rem;
}

figure {
  margin: 2rem 0;
}

figcaption {
  margin-top: 0.5rem;
  color: var(--muted);
  font-size: 0.875rem;
  text-align: center;
}

code {
  font-family: var(--mono);
  font-variant-ligatures: contextual;
  font-size: 0.875em;
}

p code {
  background: var(--inline-code-bg);
  color: var(--inline-code-fg);
  border-radius: 0.25rem;
  padding: 0.1em 0.35em;
}

/*
 * Code blocks mimic the "Luba" Xcode theme verbatim (colors pulled directly from
 * ~/Library/Developer/Xcode/UserData/FontAndColorThemes/Luba.xccolortheme) rather than
 * following the page's own light/dark toggle — it's a dark editor theme, so the block
 * stays a fixed dark "editor" island regardless of page mode.
 *
 * These hex values (pre's background/color, every .token-* rule below) are duplicated in
 * `SwiftHighlightTheme.swift` as the source the native article editor reads for live syntax
 * highlighting. They aren't generated from that table — this is a plain string literal — so
 * a color changed here must be changed there too.
 */
pre {
  background: #1e2028;
  border: 1px solid #2c2f36;
  border-radius: 0.5rem;
  padding: 1rem;
  overflow-x: auto;
  margin: 0 0 1.25em;
  color: #ffffff;
}

.token-keyword { color: #ffe400; }
.token-string, .token-regex { color: #ff2700; }
.token-number { color: #ff00e3; }
.token-comment { color: #16ff00; font-style: italic; }
.token-comment-doc { color: #17bf06; font-style: italic; }
.token-mark { color: #92a1b1; font-style: italic; font-weight: 600; }
.token-attribute { color: #22fef0; }
.token-declaration-type { color: #5dd8ff; font-weight: 600; }
.token-declaration-other { color: #41a1c0; }
.token-type { color: #3ea58f; }
.token-variable { color: #65dcf3; }
.token-function-call { color: #3f90cf; }
.token-constant { color: #00ffc1; }
.token-macro { color: #e58800; }
.token-preprocessor { color: #ff8f04; }

footer {
  margin-top: 3rem;
  padding-top: 1rem;
  border-top: 1px solid var(--code-border);
  color: var(--muted);
  font-size: 0.875rem;
}
"""
