import SwiftUI

/// The day a sheet is about: its id, to present the sheet with.
struct AskedDay: Identifiable, Hashable {
    let id: UUID
}

/// "How was the snow?": asked when a day ends, on the iPhone or arriving from the watch. The
/// answer stays with the day and, if you leave the switches on, is told to who skis there.
struct SnowSheet: View {
    let id: UUID
    @Environment(Library.self) private var library
    @Environment(Social.self) private var social
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.tellSnow) private var tell = true
    @AppStorage(Prefs.tellFriends) private var tellFriends = true
    @State private var day: DaySummary?
    @State private var picked: Snow?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Com'era la neve?").font(.display(.title2)).foregroundStyle(Theme.text)
                        if let day {
                            Text("\(day.title ?? String(localized: "Giornata")) · \(Fmt.day(day.start))")
                                .font(.subheadline).foregroundStyle(Theme.sub)
                            Text("\(day.stats.runs) discese · \(Fmt.height(day.stats.vertical)) · \(Fmt.distance(day.stats.runDistance))")
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Snow.allCases) { snow in
                            Button { picked = picked == snow ? nil : snow } label: { SnowChoice(snow: snow, chosen: picked == snow) }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(picked == snow ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: picked)
                    if social.signedIn, day?.lat != nil {
                        Panel("Dillo a chi scia qui") {
                            Toggle(isOn: $tell) {
                                Text("Com'era la neve e i numeri della giornata").font(.subheadline).foregroundStyle(Theme.text)
                            }
                            .tint(Theme.accent)
                            Toggle(isOn: $tellFriends) {
                                Text("Fai vedere agli amici che c'ero").font(.subheadline).foregroundStyle(Theme.text)
                            }
                            .tint(Theme.accent)
                            .disabled(!tell)
                            Text("Chi apre questa stazione vede com'era la neve e le medie delle giornate di tutti, senza nomi. Parte la zona al chilometro, mai la traccia. Il tuo nome lo vedono solo i tuoi amici, e solo se lasci acceso il secondo interruttore.")
                                .prose().font(.caption).foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if !social.signedIn {
                        Text("La risposta resta con la giornata. Con un account (in Amici) puoi dirlo anche a chi scia nella stessa stazione.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Label("Salva", systemImage: "checkmark") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving || (picked == nil && day?.lat == nil))
                }
                .padding(16)
            }
            .screen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Non ora") { dismiss() } }
            }
            .task {
                day = library.days.first { $0.id == id }
                picked = library.day(id)?.snow
            }
        }
        .modifier(Dressed())
        .presentationDetents([.large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var told = false
        if let day, social.signedIn, tell, day.lat != nil {
            told = await social.tell(day, snow: picked, numbers: true, friends: tellFriends)
        }
        library.setSnow(id, to: picked, told: told)
        dismiss()
    }
}

/// One kind of snow to choose.
private struct SnowChoice: View {
    let snow: Snow
    let chosen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snow.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chosen ? Theme.onAccent : Theme.accent)
                .frame(width: 34, height: 34)
                .background(chosen ? Theme.accent : Theme.deep, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(snow.label)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(LocalizedStringKey(snow.hint)).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: Theme.roundSmall)
        .overlay(Theme.roundSmall.strokeBorder(chosen ? Theme.accent : Theme.line, lineWidth: chosen ? 2 : 1))
    }
}

/// How the snow is at a ski area, from who skied there in the last days, and the average day.
struct CommunityPanel: View {
    let lat: Double
    let lon: Double
    @Environment(Social.self) private var social
    @State private var info: PlaceInfo?
    @State private var asked = false

    var body: some View {
        Group {
            if !social.signedIn {
                Panel("Community") {
                    Text("Con un account (in Amici) vedi com'è la neve secondo chi ha sciato qui, le medie delle giornate e quali amici ci sono stati.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let info {
                snow(info)
                if !info.friends.isEmpty || info.averages != nil { people(info) }
            } else if !asked {
                ProgressView().padding(12)
            }
        }
        .task(id: social.account?.id) {
            info = await social.place(lat: lat, lon: lon)
            asked = true
        }
    }

    private func snow(_ info: PlaceInfo) -> some View {
        Panel("Com'è la neve") {
            if let latest = info.latest, let kind = latest.snow {
                HStack(spacing: 12) {
                    Image(systemName: kind.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(kind.label)).font(.headline).foregroundStyle(Theme.text)
                        Text(Self.ago(latest.date)).font(.caption).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                }
                if info.snow.count > 1 || info.reports > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(info.snow) { count in
                                if let snow = count.snow {
                                    Chip(symbol: snow.symbol, text: "\(String(localized: String.LocalizationValue(snow.label))) \(count.count)", color: Theme.accent)
                                }
                            }
                        }
                    }
                }
                Text("Da chi ha sciato qui negli ultimi cinque giorni: \(info.reports) giornate.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
            } else {
                Text("Nessuno l'ha ancora detto negli ultimi giorni. Dopo una giornata qui, puoi dirlo tu.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func people(_ info: PlaceInfo) -> some View {
        Panel("Chi è stato qui") {
            if info.friends.isEmpty {
                Text("Nessuno dei tuoi amici ha detto di aver sciato qui.").font(.caption).foregroundStyle(Theme.sub)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(info.friends) { friend in
                            VStack(spacing: 5) {
                                Avatar(id: friend.id, name: friend.name, photo: friend.photo, size: 46)
                                Text(friend.name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(friend.days) g").font(.caption2).foregroundStyle(Theme.sub)
                            }
                            .frame(width: 66)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if let mean = info.averages {
                Divider().overlay(Theme.line)
                Text("Giornata media qui").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 12) {
                    Mean(value: Fmt.height(mean.vertical), label: "Dislivello", symbol: "arrow.down")
                    Mean(value: Fmt.distance(mean.distance), label: "Distanza", symbol: "arrow.right")
                    Mean(value: Fmt.duration(mean.runTime), label: "In discesa", symbol: "clock")
                    Mean(value: Fmt.duration(mean.liftTime), label: "In risalita", symbol: "clock.arrow.circlepath")
                    Mean(value: Fmt.speed(mean.avgSpeed), label: "Vel. media", symbol: "speedometer")
                    Mean(value: mean.runs.formatted(.number.precision(.fractionLength(0))), label: "Discese", symbol: "arrow.triangle.2.circlepath")
                }
                Text("Media di \(mean.days) giornate di chi ha scelto di dirlo, senza nomi.")
                    .prose().font(.caption2).foregroundStyle(Theme.sub)
            }
        }
    }

    /// "oggi", "ieri", "3 giorni fa" from a yyyy-MM-dd.
    static func ago(_ date: String, now: Date = Date()) -> String {
        guard let day = PlaceInfo.dayFormat.date(from: date) else { return date }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: day), to: Calendar.current.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return String(localized: "oggi")
        case 1: return String(localized: "ieri")
        default: return String(localized: "\(days) giorni fa")
        }
    }
}

private struct Mean: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(.headline)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Label(LocalizedStringKey(label), systemImage: symbol).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
