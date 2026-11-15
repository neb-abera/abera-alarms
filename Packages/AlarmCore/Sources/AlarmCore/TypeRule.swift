import Foundation

/// One rule for what an event sends, kept on abera.tech: when the field
/// contains the text, in any case, the event's alert is the type. Blank text
/// on organizer or location matches any event that has one. The first rule
/// that matches wins, after a type chosen for the event and #critical.
public struct TypeRule: Codable, Equatable, Hashable, Sendable {
    public var field: String
    public var text: String
    /// "alarm", "notification" or "none".
    public var type: String

    public init(field: String = TypeRule.organizer, text: String = "", type: String = AlertType.alarm) {
        self.field = field
        self.text = text
        self.type = type
    }

    public static let title = "title"
    public static let organizer = "organizer"
    public static let location = "location"

    /// The bounds abera.tech checks (AlertTypeRuleBounds).
    public static let maxRules = 50
    public static let maxTextLength = 100

    /// Each field as the rule screen names it.
    public static let fields: [(value: String, label: String)] = [
        (title, "Title contains"),
        (organizer, "Organizer contains"),
        (location, "Location contains"),
    ]

    public var trimmed: TypeRule {
        TypeRule(field: field, text: text.trimmingCharacters(in: .whitespacesAndNewlines), type: type)
    }

    /// What abera.tech would refuse, by rule, so the screen says it before it sends.
    public static func problems(_ rules: [TypeRule]) -> [String] {
        var problems: [String] = []
        if rules.count > maxRules { problems.append("At most \(maxRules) rules.") }
        for (index, rule) in rules.enumerated() {
            let text = rule.trimmed.text
            if rule.field == title && text.isEmpty {
                problems.append("Rule \(index + 1): a title rule needs a word to look for.")
            }
            if text.count > maxTextLength { problems.append("Rule \(index + 1): at most \(maxTextLength) characters.") }
        }
        return problems
    }

    /// As abera.tech matches: the field contains the text, in any case.
    public func matches(title: String, organizer: String?, location: String?) -> Bool {
        let value: String? =
            switch field {
            case Self.title: title
            case Self.organizer: organizer
            case Self.location: location
            default: nil
            }
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return text.isEmpty || value.range(of: text, options: .caseInsensitive) != nil
    }
}

/// The body of PUT /api/alerts/rules: the whole ordered list.
struct RulesBody: Encodable, Sendable {
    var rules: [TypeRule]
}
