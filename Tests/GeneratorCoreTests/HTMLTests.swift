import CoreFP
import CoreFPOperators
import Testing

@testable import GeneratorCore

@Suite("HTML")
struct HTMLTests {
    @Test("escapes reserved characters in text")
    func escapesText() {
        let html = HTML.text("<script>alert(1)</script> & \"quotes\"")

        #expect(html.rendered == "&lt;script&gt;alert(1)&lt;/script&gt; &amp; \"quotes\"")
    }

    @Test("raw content is not escaped")
    func rawIsNotEscaped() {
        let html = HTML.raw("<b>bold</b>")

        #expect(html.rendered == "<b>bold</b>")
    }

    @Test("wraps children in an element with sorted, escaped attributes")
    func elementWithAttributes() {
        let html = element("img", .identity, attributes: ["src": "a.png", "alt": "a \"cat\""])

        #expect(html.rendered == "<img alt=\"a &quot;cat&quot;\" src=\"a.png\"></img>")
    }

    @Test("void element has no closing tag")
    func voidElementRendersSelfClosing() {
        let html = voidElement("img", attributes: ["src": "a.png"])

        #expect(html.rendered == "<img src=\"a.png\" />")
    }

    @Test("Monoid identity is a left and right identity for combine")
    func monoidIdentityLaws() {
        let html = HTML.text("hello")

        #expect(HTML.combine(.identity, html).rendered == html.rendered)
        #expect(HTML.combine(html, .identity).rendered == html.rendered)
    }

    @Test("combine concatenates markup, and <> delegates to it")
    func combineConcatenates() {
        let lhs = HTML.text("a")
        let rhs = HTML.text("b")

        #expect(HTML.combine(lhs, rhs).rendered == "ab")
        #expect((lhs <> rhs).rendered == "ab")
    }

    @Test("mconcat folds a list of HTML fragments in order")
    func mconcatFoldsInOrder() {
        let html = mconcat([HTML.text("a"), HTML.text("b"), HTML.text("c")])

        #expect(html.rendered == "abc")
    }
}
