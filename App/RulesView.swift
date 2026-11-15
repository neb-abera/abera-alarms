import AlarmCore
import SwiftUI

/// The rules for what an event sends when it has no type of its own and no
/// #critical mark, as one ordered list saved on abera.tech. The page at
/// abera.tech/alerts edits the same list.
struct RulesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [TypeRule]

    init(model: AppModel) {
        self.model = model
        _rules = State(initialValue: model.rules)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(rules.indices, id: \.self) { index in
                        RuleRow(rule: $rules[index], number: index + 1)
                    }
                    .onDelete { rules.remove(atOffsets: $0) }
                    .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Rule") { rules.append(TypeRule()) }
                        .disabled(rules.count >= TypeRule.maxRules)
                        .accessibilityIdentifier("add-rule")
                } footer: {
                    Text(
                        "A rule sets what an event sends when it has no type of its own and no #critical mark. The first rule that matches wins. Matching ignores case. Organizer and location rules with no text match any event that has one."
                    )
                }
                ForEach(TypeRule.problems(rules), id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let error = model.rulesError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("rules-error")
                }
            }
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.saveRules(rules) { dismiss() }
                        }
                    }
                    .disabled(!TypeRule.problems(rules).isEmpty || model.busy || rules == model.rules)
                    .accessibilityIdentifier("save-rules")
                }
            }
            .onAppear { model.clearRulesError() }
        }
    }
}

/// One rule: what it looks at, the text, and what it sends.
private struct RuleRow: View {
    @Binding var rule: TypeRule
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("When", selection: $rule.field) {
                ForEach(TypeRule.fields, id: \.value) { field in
                    Text(field.label).tag(field.value)
                }
            }
            .accessibilityIdentifier("rule-\(number)-field")
            TextField(placeholder, text: $rule.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("rule-\(number)-text")
            Picker("Sends", selection: $rule.type) {
                ForEach([AlertType.alarm, AlertType.notification, AlertType.none], id: \.self) { type in
                    Text(TypeMenu.name(type)).tag(type)
                }
            }
            .accessibilityIdentifier("rule-\(number)-type")
        }
        .padding(.vertical, 4)
    }

    private var placeholder: String {
        switch rule.field {
        case TypeRule.title: "A word in the title"
        case TypeRule.organizer: "army.mil, or blank for any organizer"
        default: "Blank for any location"
        }
    }
}
