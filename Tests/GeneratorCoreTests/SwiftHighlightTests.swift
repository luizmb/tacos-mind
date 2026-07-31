import Testing

@testable import GeneratorCore

@Suite("highlightSwift")
struct SwiftHighlightTests {
    @Test("classifies a keyword")
    func classifiesKeyword() {
        #expect(highlightSwift("let x = 1").rendered.contains("<span class=\"token-keyword\">let</span>"))
    }

    @Test("classifies a let-bound name as declaration-other")
    func classifiesLetBinding() {
        #expect(highlightSwift("let x = 1").rendered.contains("<span class=\"token-declaration-other\">x</span>"))
    }

    @Test("classifies a function declaration's name as declaration-other")
    func classifiesFunctionDeclarationName() {
        let html = highlightSwift("func square(_ x: Int) -> Int { x * x }").rendered

        #expect(html.contains("<span class=\"token-declaration-other\">square</span>"))
    }

    @Test("classifies a function parameter name as declaration-other")
    func classifiesParameterName() {
        let html = highlightSwift("func square(_ x: Int) -> Int { x * x }").rendered

        #expect(html.contains("<span class=\"token-declaration-other\">x</span>"))
    }

    @Test("classifies a closure's shorthand parameter name as declaration-other")
    func classifiesClosureParameterName() {
        let html = highlightSwift("{ b in b + 1 }").rendered

        #expect(html.contains("<span class=\"token-declaration-other\">b</span>"))
    }

    @Test("classifies a class/struct/enum declaration's name as declaration-type")
    func classifiesTypeDeclarationName() {
        #expect(highlightSwift("struct Foo {}").rendered.contains("<span class=\"token-declaration-type\">Foo</span>"))
        #expect(highlightSwift("class Foo {}").rendered.contains("<span class=\"token-declaration-type\">Foo</span>"))
        #expect(highlightSwift("enum Foo {}").rendered.contains("<span class=\"token-declaration-type\">Foo</span>"))
    }

    @Test("classifies a type usage (annotation/return type) as type")
    func classifiesTypeUsage() {
        let html = highlightSwift("func square(_ x: Int) -> Int { x * x }").rendered

        #expect(html.contains("<span class=\"token-type\">Int</span>"))
    }

    @Test("classifies an integer literal")
    func classifiesIntegerLiteral() {
        #expect(highlightSwift("let x = 1").rendered.contains("<span class=\"token-number\">1</span>"))
    }

    @Test("classifies a string literal's quotes and content")
    func classifiesStringLiteral() {
        let html = highlightSwift(#"let s = "hi""#).rendered

        #expect(html.contains("<span class=\"token-string\">\"</span>"))
        #expect(html.contains("<span class=\"token-string\">hi</span>"))
    }

    @Test("classifies a plain value reference as variable")
    func classifiesVariableReference() {
        let html = highlightSwift("let y = x").rendered

        #expect(html.contains("<span class=\"token-variable\">x</span>"))
    }

    @Test("classifies a called name as function-call")
    func classifiesFunctionCall() {
        let html = highlightSwift("square(5)").rendered

        #expect(html.contains("<span class=\"token-function-call\">square</span>"))
    }

    @Test("classifies a called method (member access) as function-call")
    func classifiesMethodCall() {
        let html = highlightSwift("numbers.map(addFive)").rendered

        #expect(html.contains("<span class=\"token-function-call\">map</span>"))
        #expect(html.contains("<span class=\"token-variable\">numbers</span>"))
    }

    @Test("classifies an implicit member expression as constant")
    func classifiesImplicitMemberConstant() {
        let html = highlightSwift("let c: Color = .red").rendered

        #expect(html.contains("<span class=\"token-constant\">red</span>"))
    }

    @Test("classifies an attribute name")
    func classifiesAttribute() {
        let html = highlightSwift("@Sendable func f() {}").rendered

        #expect(html.contains("<span class=\"token-attribute\">Sendable</span>"))
    }

    @Test("classifies a macro expansion name")
    func classifiesMacro() {
        let html = highlightSwift("#warning(\"todo\")").rendered

        #expect(html.contains("<span class=\"token-macro\">warning</span>"))
    }

    @Test("classifies a preprocessor directive")
    func classifiesPreprocessor() {
        let html = highlightSwift("#if DEBUG\nlet x = 1\n#endif").rendered

        #expect(html.contains("<span class=\"token-preprocessor\">#if</span>"))
        #expect(html.contains("<span class=\"token-preprocessor\">#endif</span>"))
    }

    @Test("classifies a line comment and preserves its text")
    func classifiesLineComment() {
        let html = highlightSwift("let x = 1 // one").rendered

        #expect(html.contains("<span class=\"token-comment\">// one</span>"))
    }

    @Test("classifies a doc comment distinctly from a regular comment")
    func classifiesDocComment() {
        let html = highlightSwift("/// Docs\nlet x = 1").rendered

        #expect(html.contains("<span class=\"token-comment-doc\">/// Docs</span>"))
    }

    @Test("classifies a MARK comment distinctly from a regular comment")
    func classifiesMarkComment() {
        let html = highlightSwift("// MARK: - Section\nlet x = 1").rendered

        #expect(html.contains("<span class=\"token-mark\">// MARK: - Section</span>"))
        #expect(!html.contains("token-comment\">// MARK"))
    }

    @Test("escapes reserved characters inside tokens and comments")
    func escapesReservedCharacters() {
        let html = highlightSwift("let x = a < b // a < b").rendered

        #expect(!html.contains("<b>"))
        #expect(html.contains("&lt;"))
    }

    @Test("preserves whitespace between tokens")
    func preservesWhitespace() {
        let html = highlightSwift("let   x = 1").rendered

        #expect(html.contains("token-keyword\">let</span>   <span"))
    }
}
