import SwiftUI

/// Friends: the leaderboards of a season among you and the people you invited, and the account
/// they need.
struct FriendsView: View {
    @Environment(Social.self) private var social
    @Environment(Library.self) private var library
    @State private var season: Season?
    @State private var metric = BoardMetric.days
    @State private var typingCode = false
    @State private var code = ""

    private var seasons: [Season] {
        Array(Set(library.seasons + [Season(Date())])).sorted(by: >)
    }

    private var current: Season { season ?? Season(Date()) }

    var body: some View {
        @Bindable var social = social
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ErrorBanner(error: $social.error)
                    if social.signedIn {
                        board
                        LiveFriendsPanel()
                        invite
                        people
                        profileLink
                    } else {
                        SignInPanel()
                    }
                    Text("Con gli amici condividi il nome, la foto se la metti e i totali della stagione: giorni, discese, dislivello, chilometri, tempo e velocità massima. La posizione la vedono solo se accendi \"Fatti vedere dagli amici\", e solo mentre registri. Le tracce e i posti delle tue giornate restano sul tuo iPhone.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Amici")
            .toolbar {
                if social.busy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .refreshable { await social.refresh(season: current, days: library.days) }
            .task(id: "\(current.year)-\(social.account?.id ?? "")-\(library.saves)") {
                await social.refresh(season: current, days: library.days)
            }
            .task(id: social.pendingCode) { await acceptPending() }
            .alert("Codice dell'invito", isPresented: $typingCode) {
                TextField("Codice di 8 caratteri", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Aggiungi") {
                    Task {
                        if await social.accept(code) { await social.refresh(season: current, days: library.days) }
                        code = ""
                    }
                }
                Button("Annulla", role: .cancel) { code = "" }
            } message: {
                Text("Scrivi il codice che ti ha mandato il tuo amico.")
            }
        }
    }

    /// An invitation opened from a link is accepted as soon as there is an account.
    private func acceptPending() async {
        guard social.signedIn, let pending = social.pendingCode else { return }
        social.pendingCode = nil
        if await social.accept(pending) { await social.refresh(season: current, days: library.days) }
    }

    // MARK: The leaderboard

    private var board: some View {
        let ranked = metric.ranked(social.rows)
        return VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { s in
                            pill(s.label, on: s == current) { season = s }
                        }
                    }
                }
            } else {
                Text("STAGIONE \(current.label)").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BoardMetric.allCases) { m in
                        pill(String(localized: String.LocalizationValue(m.label)), on: m == metric) { metric = m }
                    }
                }
            }
            Panel {
                if ranked.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(20)
                }
                ForEach(ranked, id: \.row.id) { entry in
                    HStack(spacing: 12) {
                        Text("\(entry.place)").font(.display(.subheadline)).monospacedDigit()
                            .foregroundStyle(entry.row.me ? Theme.accent : Theme.sub)
                            .frame(width: 22)
                        Avatar(id: entry.row.id, name: entry.row.name, photo: entry.row.photo, size: 36,
                               ring: entry.row.me ? Theme.accent : nil)
                        Text(entry.row.name).font(.subheadline.weight(entry.row.me ? .bold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                        if entry.row.me {
                            Text("tu").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        Spacer(minLength: 6)
                        Text(metric.text(entry.row)).font(.display(.subheadline)).monospacedDigit()
                            .foregroundStyle(entry.row.me ? Theme.accent : Theme.text)
                    }
                    .accessibilityElement(children: .combine)
                    if entry.row.id != ranked.last?.row.id { Divider().overlay(Theme.line) }
                }
                if ranked.count == 1 {
                    Text("Per ora ci sei solo tu: invita un amico per iniziare la classifica.")
                        .prose().font(.caption).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func pill(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(text).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(on ? Theme.onAccent : Theme.text)
                .background(on ? Theme.accent : Theme.input, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Invitations and friends

    private var invite: some View {
        Panel("Invita un amico") {
            if let link = social.inviteLink, let code = social.inviteCode {
                Text(code).font(.display(.title3)).tracking(3).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                ShareLink(item: link, message: Text("Sfidami su Ski Apex: apri il link per diventare amici.")) {
                    Label("Manda il link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Il link vale una settimana e può usarlo più di una persona.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
            } else {
                Button { Task { await social.makeInvite() } } label: { Label("Crea il link di invito", systemImage: "link") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button { typingCode = true } label: { Label("Ho un codice", systemImage: "keyboard") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder private var people: some View {
        if !social.friends.isEmpty {
            Panel("I tuoi amici") {
                ForEach(social.friends) { friend in
                    HStack {
                        Avatar(id: friend.id, name: friend.name, photo: friend.photo, size: 36)
                        Text(friend.name).font(.subheadline).foregroundStyle(Theme.text)
                        Spacer()
                        Menu {
                            Button(role: .destructive) { Task { await social.remove(friend) } } label: {
                                Label("Togli dagli amici", systemImage: "person.badge.minus")
                            }
                        } label: {
                            Label("Altro", systemImage: "ellipsis").labelStyle(.iconOnly)
                                .foregroundStyle(Theme.sub)
                                .frame(width: 44, height: 44)
                        }
                    }
                }
            }
        }
    }

    /// Your picture and your name: the way to the profile.
    @ViewBuilder private var profileLink: some View {
        if let account = social.account {
            NavigationLink {
                ProfileView()
            } label: {
                HStack(spacing: 12) {
                    Avatar(id: account.id, name: account.name, photo: account.photo, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("Foto, account e uscita").font(.caption).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .buttonStyle(PressStyle())
        }
    }
}
