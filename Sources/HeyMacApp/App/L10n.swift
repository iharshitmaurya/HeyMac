import Foundation

/// Looks up a translated runtime string in the app bundle, falling back to its
/// English source value. SwiftUI string literals already perform this lookup.
enum L10n {
    static func text(_ source: String, comment: String = "") -> String {
        NSLocalizedString(source, tableName: "Localizable", bundle: .main, value: source, comment: comment)
    }

    static func format(_ source: String, _ arguments: CVarArg..., comment: String = "") -> String {
        let template = text(source, comment: comment)
        return String(format: template, locale: Locale.current, arguments: arguments)
    }

    static func plural(_ key: String, count: Int) -> String {
        let template = NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: "%#@count@", comment: "")
        return String.localizedStringWithFormat(template, count)
    }

    static func plural(_ key: String, count: Int, total: Int) -> String {
        let template = NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: "%#@count@", comment: "")
        return String.localizedStringWithFormat(template, count, total)
    }
}
