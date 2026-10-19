import SwiftUI

public extension L {
    /// A word the domain carries in English (a field's vocabulary, a unit, a backdrop's name),
    /// in the reader's language: the catalog holds it under the same English key.
    static func domain(_ english: String) -> LocalizedStringKey {
        LocalizedStringKey(english)
    }
}

public extension L {
    /// The same word as a string, for a format that takes one (a unit inside "Duration (%@)").
    static func domainString(_ english: String) -> String {
        String(localized: String.LocalizationValue(english))
    }
}

public extension Text {
    /// Several messages read one after another, in the reader's language: sentences joined by a
    /// space, or the parts of a status line by " · ".
    init(joining parts: [LocalizedStringResource], separator: String = " ") {
        self = parts.dropFirst().reduce(Text(parts.first ?? "")) { $0 + Text(verbatim: separator) + Text($1) }
    }
}
