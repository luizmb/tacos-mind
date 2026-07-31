import CoreFP
import Foundation
import SwiftParser
import SwiftSyntax

/// One classified run of source text: `category` is a `token-*` CSS class name (matching
/// `Stylesheet.swift` and `swiftHighlightColors`), or `nil` for unstyled trivia (whitespace,
/// non-MARK/doc comments' surrounding punctuation is still styled — only plain whitespace
/// and blank trivia end up `nil`). Concatenating every segment's `text` in order exactly
/// reconstructs the original source — this is a SwiftSyntax invariant (leading trivia +
/// token text + trailing trivia, for every token in source order, has no gaps or overlaps)
/// — which is what lets `swiftHighlightTokens(in:)` compute UTF-16 ranges by just summing
/// segment lengths, without ever touching SwiftSyntax's byte-offset `AbsolutePosition` API.
public struct SwiftHighlightSegment: Sendable, Equatable {
    public let text: String
    public let category: String?
}

/// One classified span of `source`, in UTF-16 (`NSRange`) terms — the same space
/// `NSTextView`/`UITextView` and their `NSAttributedString` backing use. Only styled spans
/// are included (plain whitespace/trivia is omitted, same as `highlightSwift` only wrapping
/// styled segments in a `<span>`).
public struct SwiftHighlightToken: Sendable, Equatable {
    public let range: NSRange
    public let category: String
}

/// Classifies `source` as Swift code, matching the generated site's own highlighting
/// (`highlightSwift`, used to render code blocks) exactly — same categories, same rules.
/// For editors that want to color live text (not render HTML).
public func swiftHighlightTokens(in source: String) -> [SwiftHighlightToken] {
    var tokens: [SwiftHighlightToken] = []
    var utf16Offset = 0
    for segment in classifiedSegments(source) {
        let length = (segment.text as NSString).length
        if let category = segment.category {
            tokens.append(SwiftHighlightToken(range: NSRange(location: utf16Offset, length: length), category: category))
        }
        utf16Offset += length
    }
    return tokens
}

func highlightSwift(_ source: String) -> HTML {
    mconcat(classifiedSegments(source).map { segment in
        guard let category = segment.category else { return .text(segment.text) }
        return span("token-\(category)", .text(segment.text))
    })
}

func classifiedSegments(_ source: String) -> [SwiftHighlightSegment] {
    Parser.parse(source: source).tokens(viewMode: .sourceAccurate).flatMap(segmentsForToken)
}

func segmentsForToken(_ token: TokenSyntax) -> [SwiftHighlightSegment] {
    var segments = triviaSegments(token.leadingTrivia)
    if !token.text.isEmpty {
        segments.append(SwiftHighlightSegment(text: token.text, category: classify(token)))
    }
    segments.append(contentsOf: triviaSegments(token.trailingTrivia))
    return segments
}

func triviaSegments(_ trivia: Trivia) -> [SwiftHighlightSegment] {
    trivia.map(triviaPieceSegment)
}

func triviaPieceSegment(_ piece: TriviaPiece) -> SwiftHighlightSegment {
    switch piece {
    case .lineComment, .blockComment:
        SwiftHighlightSegment(text: triviaPieceText(piece), category: isMarkComment(piece) ? "mark" : "comment")
    case .docLineComment, .docBlockComment:
        SwiftHighlightSegment(text: triviaPieceText(piece), category: "comment-doc")
    default:
        SwiftHighlightSegment(text: triviaPieceText(piece), category: nil)
    }
}

/// Classifies a token by its own kind first, then — for identifiers, whose meaning depends on
/// where they sit in the tree — by inspecting its parent (and, for calls/member access, its
/// grandparent). This mirrors categories Xcode's syntax coloring makes from pure syntax; it
/// cannot mimic Xcode's semantic-only distinctions (stdlib vs user symbol, "character" vs
/// "string" literal), since those require type-checking, not just parsing.
func classify(_ token: TokenSyntax) -> String {
    switch token.tokenKind {
    case .keyword:
        "keyword"
    case .integerLiteral, .floatLiteral:
        "number"
    case .stringQuote, .multilineStringQuote, .stringSegment, .singleQuote, .rawStringPoundDelimiter:
        "string"
    case .regexSlash, .regexLiteralPattern, .regexPoundDelimiter:
        "regex"
    case .poundIf, .poundElse, .poundElseif, .poundEndif, .poundAvailable, .poundUnavailable, .poundSourceLocation:
        "preprocessor"
    case .pound where isMacroPound(token):
        "macro"
    case .atSign where token.parent?.is(AttributeSyntax.self) == true:
        "attribute"
    case .identifier, .dollarIdentifier:
        classifyIdentifier(token)
    default:
        "punctuation"
    }
}

func isMacroPound(_ token: TokenSyntax) -> Bool {
    if let expansion = token.parent?.as(MacroExpansionExprSyntax.self) {
        return expansion.pound == token
    }
    if let expansion = token.parent?.as(MacroExpansionDeclSyntax.self) {
        return expansion.pound == token
    }
    return false
}

func classifyIdentifier(_ token: TokenSyntax) -> String {
    if isAttributeName(token) {
        "attribute"
    } else if isMacroName(token) {
        "macro"
    } else if isTypeDeclarationName(token) {
        "declaration-type"
    } else if isOtherDeclarationName(token) {
        "declaration-other"
    } else if let type = token.parent?.as(IdentifierTypeSyntax.self), type.name == token {
        "type"
    } else if let reference = token.parent?.as(DeclReferenceExprSyntax.self), reference.baseName == token {
        classifyReference(reference)
    } else {
        "punctuation"
    }
}

func isAttributeName(_ token: TokenSyntax) -> Bool {
    guard let type = token.parent?.as(IdentifierTypeSyntax.self), type.name == token else { return false }
    return type.parent?.is(AttributeSyntax.self) == true
}

func isMacroName(_ token: TokenSyntax) -> Bool {
    if let expansion = token.parent?.as(MacroExpansionExprSyntax.self) {
        return expansion.macroName == token
    }
    if let expansion = token.parent?.as(MacroExpansionDeclSyntax.self) {
        return expansion.macroName == token
    }
    return false
}

func isTypeDeclarationName(_ token: TokenSyntax) -> Bool {
    if let decl = token.parent?.as(ClassDeclSyntax.self), decl.name == token { return true }
    if let decl = token.parent?.as(StructDeclSyntax.self), decl.name == token { return true }
    if let decl = token.parent?.as(EnumDeclSyntax.self), decl.name == token { return true }
    if let decl = token.parent?.as(ProtocolDeclSyntax.self), decl.name == token { return true }
    if let decl = token.parent?.as(TypeAliasDeclSyntax.self), decl.name == token { return true }
    return false
}

func isOtherDeclarationName(_ token: TokenSyntax) -> Bool {
    if let decl = token.parent?.as(FunctionDeclSyntax.self), decl.name == token { return true }
    if let pattern = token.parent?.as(IdentifierPatternSyntax.self), pattern.identifier == token { return true }
    if let parameter = token.parent?.as(FunctionParameterSyntax.self) {
        return parameter.firstName == token || parameter.secondName == token
    }
    if let parameter = token.parent?.as(ClosureParameterSyntax.self) {
        return parameter.firstName == token || parameter.secondName == token
    }
    if let parameter = token.parent?.as(ClosureShorthandParameterSyntax.self), parameter.name == token {
        return true
    }
    return false
}

/// A `DeclReferenceExprSyntax` is a *use* of a name (never a declaration). Its role — plain
/// value, function call, or an implicit-member constant like `.red` — depends on its parent.
func classifyReference(_ reference: DeclReferenceExprSyntax) -> String {
    if isCallee(reference) {
        "function-call"
    } else if isImplicitMemberConstant(reference) {
        "constant"
    } else {
        "variable"
    }
}

func isCallee(_ reference: DeclReferenceExprSyntax) -> Bool {
    if let call = reference.parent?.as(FunctionCallExprSyntax.self) {
        return call.calledExpression.as(DeclReferenceExprSyntax.self) == reference
    }
    if let member = reference.parent?.as(MemberAccessExprSyntax.self), member.declName == reference {
        return isCallee(inMemberAccess: member)
    }
    return false
}

func isCallee(inMemberAccess member: MemberAccessExprSyntax) -> Bool {
    guard let call = member.parent?.as(FunctionCallExprSyntax.self) else { return false }
    return call.calledExpression.as(MemberAccessExprSyntax.self) == member
}

func isImplicitMemberConstant(_ reference: DeclReferenceExprSyntax) -> Bool {
    guard let member = reference.parent?.as(MemberAccessExprSyntax.self), member.declName == reference else {
        return false
    }
    return member.base == nil
}

func isMarkComment(_ piece: TriviaPiece) -> Bool {
    var body = Substring(triviaPieceText(piece))
    while body.first == "/" || body.first == " " {
        body.removeFirst()
    }
    return body.uppercased().hasPrefix("MARK:")
}

func triviaPieceText(_ piece: TriviaPiece) -> String {
    var buffer = ""
    piece.write(to: &buffer)
    return buffer
}
