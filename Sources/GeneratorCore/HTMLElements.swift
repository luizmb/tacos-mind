import CoreFP
import CoreFPOperators

public func p(_ children: HTML) -> HTML {
    element("p", children)
}

public func pre(_ children: HTML) -> HTML {
    element("pre", children)
}

public func figure(_ children: HTML) -> HTML {
    element("figure", children)
}

public func figcaption(_ children: HTML) -> HTML {
    element("figcaption", children)
}

public func footer(_ children: HTML) -> HTML {
    element("footer", children)
}

public func code(_ children: HTML, language: String? = nil) -> HTML {
    element("code", children, attributes: language.map { ["class": "language-\($0)"] } ?? [:])
}

public func em(_ children: HTML) -> HTML {
    element("em", children)
}

public func span(_ className: String, _ children: HTML) -> HTML {
    element("span", children, attributes: ["class": className])
}

public func img(src: String, alt: String) -> HTML {
    voidElement("img", attributes: ["src": src, "alt": alt])
}

public func video(src: String) -> HTML {
    element("video", .identity, attributes: ["src": src, "controls": "controls"])
}

public func h1(_ children: HTML) -> HTML {
    element("h1", children)
}

public func h2(_ children: HTML) -> HTML {
    element("h2", children)
}

public func h3(_ children: HTML) -> HTML {
    element("h3", children)
}

public func ul(_ children: HTML, attributes: [String: String] = [:]) -> HTML {
    element("ul", children, attributes: attributes)
}

public func li(_ children: HTML) -> HTML {
    element("li", children)
}

public func a(href: String, _ children: HTML) -> HTML {
    element("a", children, attributes: ["href": href])
}

/// External links open in a new tab; `noopener` keeps the target page from reaching
/// back into ours via `window.opener`.
public func externalLink(href: String, _ children: HTML) -> HTML {
    element("a", children, attributes: ["href": href, "target": "_blank", "rel": "noopener"])
}

/// Links are site-root-absolute ("/style.css", not "./style.css" or "../style.css")
/// deliberately: relative paths break under clean-URL rewriting (e.g. `/index.html` ->
/// `/index` -> `/` redirect chains some static hosts perform), since each redirect changes
/// the directory depth the browser resolves relative links against. Absolute paths are
/// immune to that — they require `dist/` itself to be the site's webroot, which is also
/// the actual deployment target, not an assumption unique to local preview.
public func htmlDocument(title: String, tagStrip: HTML = .identity, body: HTML) -> HTML {
    .raw("""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>\(escapeText(title))</title>
    <link rel="stylesheet" href="/style.css" />
    <link rel="me" href="https://functional.cafe/@luiz" />
    </head>
    <body>
    \(header(tagStrip: tagStrip).markup)
    <main class="article">
    \(body.markup)
    </main>
    </body>
    </html>
    """)
}

func header(tagStrip: HTML = .identity) -> HTML {
    element("header", element("nav", a(href: "/index.html", .text("ios.lu")) <> tagStrip))
}
