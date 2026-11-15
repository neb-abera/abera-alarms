import Foundation
import Testing

@testable import AlarmCore

/// Rules for what an event sends: read from abera.tech, checked before
/// they are sent, matched as abera.tech matches, and saved as one list.
@Suite struct TypeRuleTests {
    @Test func readsTheServersRulesInOrder() throws {
        let json = #"""
            {"configured":true,"rules":[{"field":"organizer","text":"army.mil","type":"alarm"},
            {"field":"location","text":"","type":"notification"}]}
            """#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(
            state.rules == [
                TypeRule(field: "organizer", text: "army.mil", type: "alarm"),
                TypeRule(field: "location", text: "", type: "notification"),
            ])
    }

    @Test func aServerWithoutRulesGivesNoneAndThePhonesCopyRoundTrips() throws {
        let old = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(old.rules.isEmpty)
        var state = Fixtures.state([])
        state.rules = [TypeRule(field: "title", text: "drill", type: "none")]
        let back = try ServerDates.decoder().decode(AlertsState.self, from: ServerDates.encoder().encode(state))
        #expect(back.rules == state.rules)
    }

    @Test func aTitleRuleNeedsTextAndTextHasALimit() {
        #expect(
            TypeRule.problems([
                TypeRule(field: "title", text: "  ", type: "alarm"),
                TypeRule(field: "location", text: String(repeating: "x", count: 101), type: "none"),
                TypeRule(field: "organizer", text: "", type: "alarm"),
            ]) == ["Rule 1: a title rule needs a word to look for.", "Rule 2: at most 100 characters."])
        #expect(TypeRule.problems(Array(repeating: TypeRule(), count: 51)) == ["At most 50 rules."])
    }

    @Test(arguments: [
        ("title", "DRILL", true), ("title", "dentist", false), ("organizer", "army.mil", true),
        ("organizer", "", true), ("location", "", false),
    ])
    func matchesAsTheServerDoes(field: String, text: String, matches: Bool) {
        let rule = TypeRule(field: field, text: text, type: "alarm")
        #expect(rule.matches(title: "Fire drill", organizer: "OPS@army.mil", location: nil) == matches)
    }

    @Test func savingSendsTheTrimmedListAndTheDemoServerTypesTheEventsByIt() async {
        var dinner = Fixtures.alert("dinner", inMinutes: 90)
        dinner.title = "Dinner"
        dinner.type = AlertType.none
        dinner.typeFrom = "default"
        let rig = Fixtures.rig([dinner])
        _ = await rig.sync.sync()

        let rules = [TypeRule(field: "title", text: " dinner ", type: "alarm")]
        let report = await rig.sync.perform { client throws(APIError) in try await client.saveRules(rules) }

        #expect(report.error == nil)
        let state = await rig.server.state
        #expect(state.rules == [TypeRule(field: "title", text: "dinner", type: "alarm")])
        #expect(state.alerts.first?.type == AlertType.alarm)
        #expect(state.alerts.first?.typeFrom == "rule")
        // The sync that follows the save sets the alarm on the phone.
        #expect(await rig.alarms.alarms.values.contains { $0.key == "dinner" })
    }

    @Test func aRuleTheServerRefusesIsAnErrorAndNothingChanges() async {
        let rig = Fixtures.rig([])
        _ = await rig.sync.sync()

        let report = await rig.sync.perform { client throws(APIError) in
            try await client.saveRules([TypeRule(field: "title", text: "", type: "alarm")])
        }

        #expect(report.error != nil)
        #expect(await rig.server.state.rules.isEmpty)
    }
}
