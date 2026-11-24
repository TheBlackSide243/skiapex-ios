import CoreLocation
import SwiftUI
import UIKit

extension Meeting {
    /// Its pin on a map.
    var mark: MapMark {
        MapMark(id: "meet\(id)", lat: lat, lon: lon, title: mine ? title : "\(name): \(title)", symbol: "person.2.fill",
                color: UIColor(Theme.track))
    }

    /// "Giulia · finisce alle 13:30", "Tuo · finisce alle 13:30".
    var detail: String {
        let who = mine ? String(localized: "Tuo") : name
        let end = Fmt.time(Date(timeIntervalSince1970: until / 1000))
        return "\(who) · \(String(localized: "finisce alle \(end)"))"
    }
}

/// A place to meet in a list: whose it is, where and when.
struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            Avatar(id: meeting.id, name: meeting.name, photo: meeting.photo, size: 40, ring: Theme.track)
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                Text(meeting.detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// In Friends: the places to meet set by you and by your friends, each with the way to its map.
struct MeetingsPanel: View {
    @Environment(Social.self) private var social
    @Environment(Recorder.self) private var recorder

    /// Where you are: the day under way, or the iPhone.
    private var here: CLLocationCoordinate2D? {
        if recorder.state == .recording, let point = recorder.lastPoint { return point.coordinate }
        return recorder.here?.coordinate
    }

    var body: some View {
        Panel("Punto d'incontro") {
            ForEach(social.meetings) { meeting in
                NavigationLink {
                    ExploreView(name: meeting.label.isEmpty ? String(localized: "Punto d'incontro") : meeting.label,
                                center: meeting.coordinate, meeting: meeting)
                } label: { MeetingRow(meeting: meeting) }
                    .buttonStyle(PressStyle())
                Divider().overlay(Theme.line)
            }
            if social.meetings.contains(where: { $0.mine }) {
                Button { Task { await social.clearMeeting() } } label: { Label("Togli il tuo punto", systemImage: "xmark") }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
            }
            if let here {
                NavigationLink {
                    ExploreView(name: String(localized: "Intorno a te"), center: here)
                } label: { Label("Scegli sulla mappa", systemImage: "mappin.and.ellipse") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Text("Per dire agli amici dove trovarvi apri la mappa di una stazione, tocca un rifugio, una pista o un impianto e scegli \"Troviamoci qui\". Lo vedono sulla mappa quando aprono l'app, con il percorso sulle piste per arrivarci. Finisce da solo un'ora dopo l'orario scelto, o dopo mezza giornata.")
                .prose().font(.caption).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// On the screen of the day under way: the place to meet, when a friend set one.
struct MeetingBanner: View {
    @Environment(Social.self) private var social

    var body: some View {
        if let meeting = social.meetings.first(where: { !$0.mine }) ?? social.meetings.first {
            NavigationLink {
                ExploreView(name: meeting.label.isEmpty ? String(localized: "Punto d'incontro") : meeting.label,
                            center: meeting.coordinate, meeting: meeting)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.track)
                        .frame(width: 36, height: 36)
                        .iconBox(Theme.track)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meeting.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                        Text(meeting.mine ? String(localized: "Il tuo punto d'incontro") : String(localized: "Punto d'incontro di \(meeting.name)"))
                            .font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// A place chosen on the map, about to become where to meet.
struct MeetingDraft: Identifiable {
    let id = UUID()
    let place: CLLocationCoordinate2D
    let label: String
}

/// Where to meet, before it is sent: what the place is called and, if you want, at what time.
struct MeetingEditor: View {
    let draft: MeetingDraft
    @Environment(Social.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var timed = true
    @State private var time: Date
    @State private var sending = false

    init(draft: MeetingDraft) {
        self.draft = draft
        _label = State(initialValue: draft.label)
        _time = State(initialValue: Self.soon(from: Date()))
    }

    /// Half an hour from now, on the next five minutes.
    static func soon(from now: Date) -> Date {
        let step = 300.0
        return Date(timeIntervalSinceReferenceDate: ((now.timeIntervalSinceReferenceDate + 1800) / step).rounded(.up) * step)
    }

    /// The hour chosen as the next time it comes: an hour already well past is tomorrow's.
    static func next(_ time: Date, after now: Date) -> Date {
        time < now.addingTimeInterval(-600) ? time.addingTimeInterval(86_400) : time
    }

    var body: some View {
        @Bindable var social = social
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ErrorBanner(error: $social.error)
                    if social.signedIn {
                        Panel {
                            TextField("Nome del posto", text: $label)
                                .font(.headline)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(Theme.input, in: Theme.roundSmall)
                            Toggle(isOn: $timed) {
                                Text("A un'ora precisa").font(.subheadline).foregroundStyle(Theme.text)
                            }
                            .tint(Theme.accent)
                            if timed {
                                DatePicker("Ora", selection: $time, displayedComponents: .hourAndMinute)
                                    .font(.subheadline).foregroundStyle(Theme.text)
                            }
                        }
                        Button {
                            sending = true
                            Task {
                                let done = await social.setMeeting(lat: draft.place.latitude, lon: draft.place.longitude,
                                                                   label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                   when: timed ? Self.next(time, after: Date()) : nil)
                                sending = false
                                if done { dismiss() }
                            }
                        } label: {
                            if sending { ProgressView() } else { Label("Manda agli amici", systemImage: "paperplane.fill") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sending)
                        Text("Lo vedono i tuoi amici quando aprono Ski Apex: non arriva una notifica. Sostituisce il punto che avevi mandato prima.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Per mandare un punto d'incontro serve l'account degli amici: lo trovi nella schermata Amici.")
                            .prose().font(.subheadline).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Troviamoci qui")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
        }
        .modifier(Dressed())
        .presentationDetents([.medium, .large])
    }
}

/// In Friends: the switch of the challenge on the pistes.
struct PisteChallengePanel: View {
    @Environment(Social.self) private var social
    @Environment(Library.self) private var library
    @AppStorage(Prefs.sharePistes) private var shares = false

    var body: some View {
        Panel("Sfida sulle piste") {
            Toggle(isOn: $shares) {
                Text("Sfida gli amici sulle piste").font(.subheadline).foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: shares) { _, on in
                // Off: what the server has is taken back at once.
                Task {
                    if on { await social.sharePistes(library.days) } else { await social.stopPistes() }
                }
            }
            Text("Accesa, i tuoi amici vedono le piste che hai sciato con il tuo tempo migliore su ognuna, e tu i loro: la classifica è nella pagina di ogni pista, in Giornate → Statistiche → Le tue piste. Del posto arriva al server il nome della pista e dov'è, al chilometro.")
                .prose().font(.caption).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { PistesView() } label: {
                HStack {
                    Text("Le tue piste").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}
