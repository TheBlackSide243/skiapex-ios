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
    @State private var deleting = false
    @State private var password = ""

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
                        accountPanel
                    } else {
                        SignInPanel()
                    }
                    Text("Con gli amici condividi il nome e i totali della stagione: giorni, discese, dislivello, chilometri, tempo e velocità massima. La posizione la vedono solo se accendi \"Fatti vedere dagli amici\", e solo mentre registri. Le tracce e i posti delle tue giornate restano sul tuo iPhone.")
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
            .alert("Eliminare l'account?", isPresented: $deleting) {
                SecureField("Password", text: $password)
                Button("Elimina", role: .destructive) {
                    Task {
                        _ = await social.deleteAccount(password: password)
                        password = ""
                    }
                }
                Button("Annulla", role: .cancel) { password = "" }
            } message: {
                Text("Il nome, gli amici e i totali condivisi vengono cancellati dal server. Le giornate sul tuo iPhone restano.")
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
                            .foregroundStyle(entry.row.me ? Theme.onAccent : Theme.text)
                            .frame(width: 34, height: 34)
                            .background(entry.row.me ? Theme.accent : Theme.deep, in: Circle())
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
                        Image(systemName: "person.fill").font(.footnote).foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                            .iconBox()
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

    private var accountPanel: some View {
        Panel("Account") {
            InfoRow("Nome", social.account?.name ?? "")
            Button { Task { await social.signOut() } } label: { Label("Esci", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(SecondaryButtonStyle())
            Button { deleting = true } label: { Label("Elimina l'account", systemImage: "trash") }
                .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
        }
    }
}

/// A name and a password: to make the account, or to come back to it.
private struct SignInPanel: View {
    @Environment(Social.self) private var social
    @State private var name = ""
    @State private var password = ""
    @State private var new = true

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 84, height: 84)
                    .iconBox()
                Text("Sfida i tuoi amici").font(.display(.headline)).foregroundStyle(Theme.text)
                Text("Chi ha fatto più giorni sulla neve, più dislivello, più chilometri? Crea un account, manda il link a un amico e confrontate la stagione.")
                    .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            Panel(new ? "Crea un account" : "Accedi") {
                field {
                    TextField("Nome (lo vedono i tuoi amici)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }
                field {
                    SecureField("Password (almeno 8 caratteri)", text: $password)
                        .textContentType(new ? .newPassword : .password)
                }
                Button {
                    Task { await social.enter(name: name.trimmingCharacters(in: .whitespaces), password: password, new: new) }
                } label: {
                    if social.busy { ProgressView() } else { Text(LocalizedStringKey(new ? "Crea l'account" : "Accedi")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.count < 3 || password.count < 8 || social.busy)
                Button(LocalizedStringKey(new ? "Ho già un account" : "Non ho un account")) { new.toggle() }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.deep, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}
