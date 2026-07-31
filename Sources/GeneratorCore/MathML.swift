import CoreFP

/// A small MathML vocabulary built on the same `HTML` Monoid/escaping infrastructure as the
/// rest of the renderer — MathML is just another XML vocabulary, not a separate concern.
/// Natively supported in every current evergreen browser (MathML Core), so equations need no
/// JavaScript to render, matching the build-time syntax highlighter's own reasoning.

public func math(_ children: HTML) -> HTML {
    element("math", children, attributes: ["xmlns": "http://www.w3.org/1998/Math/MathML"])
}

public func mrow(_ children: HTML) -> HTML {
    element("mrow", children)
}

public func mi(_ text: String) -> HTML {
    element("mi", .text(text))
}

public func mn(_ text: String) -> HTML {
    element("mn", .text(text))
}

public func mo(_ symbol: String) -> HTML {
    element("mo", .text(symbol))
}

public func msup(_ base: HTML, _ exponent: HTML) -> HTML {
    element("msup", mconcat([base, exponent]))
}

public func displayEquation(_ children: HTML) -> HTML {
    element("div", math(children), attributes: ["class": "equation"])
}
