import AlarmCore
import SwiftUI

/// abera.tech's date calculator: the days between two dates, or a date
/// moved by years, months, weeks and days. The arithmetic is AlarmCore's
/// (DateCalc.swift), the same rule the site uses. It needs no connection.
struct DateCalculatorView: View {
    enum Mode: String, CaseIterable {
        case between = "Between dates"
        case add = "Add or subtract"
    }

    @State private var mode = Mode.between
    @State private var start = Self.today
    @State private var end = Self.today
    @State private var includeEnd = false
    @State private var base = Self.today
    @State private var years = "0"
    @State private var months = "0"
    @State private var weeks = "0"
    @State private var days = "0"

    static var today: String { CivilDate(Date(), in: .current).iso }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Calculation", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("calc-mode")
                switch mode {
                case .between: between
                case .add: add
                }
            }
            .navigationTitle("Dates")
        }
    }

    @ViewBuilder private var between: some View {
        Section {
            DateField(title: "Start", text: $start, id: "calc-start")
            DateField(title: "End", text: $end, id: "calc-end")
            Toggle("Include the end date", isOn: $includeEnd)
                .accessibilityIdentifier("calc-include-end")
        }
        if let first = CivilDate(iso: start), let last = CivilDate(iso: end) {
            let span = DateSpan.between(first, last, includeEnd: includeEnd)
            Section {
                ResultRow(title: "Total", value: span.totalText, id: "calc-total")
                ResultRow(title: "Years, months, days", value: span.calendarText, id: "calc-ymd")
                ResultRow(title: "Weeks", value: span.weeksText, id: "calc-weeks")
                ResultRow(title: "Weekdays, Monday to Friday", value: "\(span.weekdays)", id: "calc-weekdays")
                ResultRow(title: "Hours", value: span.hours.formatted(), id: "calc-hours")
                ResultRow(title: "Minutes", value: span.minutes.formatted(), id: "calc-minutes")
                ResultRow(title: "Seconds", value: span.seconds.formatted(), id: "calc-seconds")
            } header: {
                Text("Result")
            } footer: {
                Text(
                    "\(first.weekdayName) \(first.iso) to \(last.weekdayName) \(last.iso)\(includeEnd ? ", end date included" : ""). Months are whole months from the earlier date, ending on a month's last day when it is shorter. Hours are days × 24."
                )
            }
        } else {
            Text("Write each date as YYYY-MM-DD, years 1 to 9999.")
                .foregroundStyle(.red)
                .accessibilityIdentifier("calc-error")
        }
    }

    @ViewBuilder private var add: some View {
        Section {
            DateField(title: "Date", text: $base, id: "calc-base")
            NumberField(title: "Years", text: $years, id: "calc-years")
            NumberField(title: "Months", text: $months, id: "calc-months")
            NumberField(title: "Weeks", text: $weeks, id: "calc-weeks-in")
            NumberField(title: "Days", text: $days, id: "calc-days")
        } footer: {
            Text("A minus sign subtracts. Years, then months, then weeks and days are applied in that order.")
        }
        Section("Result") {
            if let date = CivilDate(iso: base) {
                if let y = Self.number(years), let m = Self.number(months), let w = Self.number(weeks),
                    let d = Self.number(days)
                {
                    if let result = DateShift.apply(to: date, years: y, months: m, weeks: w, days: d) {
                        ResultRow(title: "Date", value: "\(result.weekdayName) \(result.iso)", id: "calc-shifted")
                    } else {
                        Text("The result is outside years 1 to 9999.").foregroundStyle(.red)
                    }
                } else {
                    Text("Write whole numbers, with a minus sign to subtract.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("calc-error")
                }
            } else {
                Text("Write the date as YYYY-MM-DD, years 1 to 9999.")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("calc-error")
            }
        }
    }

    /// A whole number, or zero when the field is empty.
    static func number(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{2212}", with: "-")
        return trimmed.isEmpty ? 0 : Int(trimmed)
    }
}

/// A date typed as YYYY-MM-DD, with a calendar beside it for picking.
struct DateField: View {
    let title: String
    @Binding var text: String
    let id: String

    private static let utc = TimeZone(identifier: "UTC")!

    /// The calendar's view of the typed date, at noon UTC so no zone moves it a day.
    private var picked: Binding<Date> {
        Binding(
            get: {
                let day = CivilDate(iso: text) ?? CivilDate(Date(), in: .current)
                return Date(timeIntervalSince1970: Double(day.dayNumber) * 86_400 + 43_200)
            },
            set: { text = CivilDate($0, in: Self.utc).iso })
    }

    var body: some View {
        HStack {
            Text(title)
            TextField("YYYY-MM-DD", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
            DatePicker(title, selection: picked, displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, Self.utc)
                .accessibilityIdentifier("\(id)-picker")
        }
    }
}

/// A whole number typed freely, negative allowed.
struct NumberField: View {
    let title: String
    @Binding var text: String
    let id: String

    var body: some View {
        HStack {
            Text(title)
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
    }
}

struct ResultRow: View {
    let title: String
    let value: String
    let id: String

    var body: some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }
}
