import SwiftUI

/// A trip planned, in the list of the days: where, when, how long to go, and the snow expected
/// if it is close enough for a forecast.
struct TripCard: View {
    let trip: Trip
    @Environment(Guide.self) private var guide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "airplane.departure").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .iconBox()
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.name).font(.display(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(dates).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(countdown).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.deep, in: Capsule())
            }
            if let resort = trip.resort, daysToGo <= 7, let days = guide.forecasts[resort.id] {
                SnowBars(days: days)
            }
        }
        .padding(16)
        .card()
        .contentShape(Rectangle())
        .task(id: trip.resort?.id) {
            if let resort = trip.resort, daysToGo <= 7 { await guide.load(resort) }
        }
    }

    private var daysToGo: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: trip.start)).day ?? 0
    }

    private var dates: String {
        let from = trip.start.formatted(.dateTime.day().month(.abbreviated))
        let to = trip.end.formatted(.dateTime.day().month(.abbreviated).year())
        return Calendar.current.isDate(trip.start, inSameDayAs: trip.end) ? to : "\(from) – \(to)"
    }

    private var countdown: String {
        let n = daysToGo
        if n <= 0 { return String(localized: "In corso") }
        if n == 1 { return String(localized: "Domani") }
        return String(localized: "Tra \(n) giorni")
    }
}

/// A trip to write or to change: where and when.
struct TripEditor: View {
    @State var trip: Trip
    var isNew = false
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Panel("Dove") {
                        TextField("Località o stazione", text: $trip.name)
                            .textInputAutocapitalization(.words)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Theme.deep, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                        if let resort = trip.resort {
                            HStack {
                                Label(resort.name, systemImage: "mountain.2").font(.caption).foregroundStyle(Theme.sub)
                                Spacer()
                                Button("Togli") { trip.resort = nil }.font(.caption)
                            }
                        } else {
                            Text("Per avere le previsioni della neve nel viaggio, crealo dalla pagina di una stazione nella Guida.")
                                .prose().font(.caption).foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Panel("Quando") {
                        DatePicker("Dal", selection: $trip.start, displayedComponents: .date)
                        DatePicker("Al", selection: $trip.end, in: trip.start..., displayedComponents: .date)
                    }
                    Button {
                        var saved = trip
                        saved.name = trip.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if saved.end < saved.start { saved.end = saved.start }
                        library.saveTrip(saved)
                        dismiss()
                    } label: { Label("Salva il viaggio", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(trip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !isNew {
                        Button {
                            library.deleteTrip(trip.id)
                            dismiss()
                        } label: { Label("Elimina il viaggio", systemImage: "trash") }
                            .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
                    }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle(LocalizedStringKey(isNew ? "Nuovo viaggio" : "Viaggio"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
            .onChange(of: trip.start) { _, start in
                if trip.end < start { trip.end = start }
            }
        }
        .modifier(Dressed())
    }
}

/// A day written by hand, for the days skied without the iPhone or before the app.
struct ManualDayView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var hours = 5.0
    @State private var sport = Sport.current
    @State private var runs = 10
    @State private var vertical = ""
    @State private var distance = ""
    @State private var speed = ""
    @State private var error: String?

    private var metric: Bool { Units.current == .metric }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ErrorBanner(error: $error)
                    Panel("Dove e quando") {
                        field("Località", text: $place, numbers: false)
                        DatePicker("Inizio", selection: $start, in: ...Date())
                        Stepper(value: $hours, in: 0.5...12, step: 0.5) {
                            Text("Durata: \(hours.formatted(.number.precision(.fractionLength(0...1)))) h").font(.subheadline)
                        }
                        Picker("Attività", selection: $sport) {
                            ForEach(Sport.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Panel("Numeri") {
                        Stepper(value: $runs, in: 0...99) {
                            Text("Discese: \(runs)").font(.subheadline)
                        }
                        field(metric ? "Dislivello (m)" : "Dislivello (ft)", text: $vertical, numbers: true)
                        field(metric ? "Chilometri sciati" : "Miglia sciate", text: $distance, numbers: true)
                        field(metric ? "Velocità max (km/h), se la sai" : "Velocità max (mph), se la sai", text: $speed, numbers: true)
                    }
                    Button { save() } label: { Label("Salva la giornata", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Attività manuale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
        }
        .modifier(Dressed())
    }

    private func field(_ title: String, text: Binding<String>, numbers: Bool) -> some View {
        TextField(LocalizedStringKey(title), text: text)
            .keyboardType(numbers ? .decimalPad : .default)
            .textInputAutocapitalization(numbers ? .never : .words)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.deep, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    /// A number typed with a comma or a point; nil when it is not one.
    static func number(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? 0 : Double(clean)
    }

    private func save() {
        guard let v = Self.number(vertical), let d = Self.number(distance), let s = Self.number(speed) else {
            error = String(localized: "Controlla i numeri: usa solo cifre.")
            return
        }
        let name = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = SkiDay(manual: start, duration: hours * 3600, place: name.isEmpty ? nil : name, sport: sport, runs: runs,
                         vertical: metric ? v : v / 3.280_84,
                         distance: metric ? d * 1000 : d * 1609.344,
                         maxSpeed: metric ? s / 3.6 : s / 2.236_94)
        do {
            try library.save(day)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
