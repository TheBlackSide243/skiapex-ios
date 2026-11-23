import AuthenticationServices
import PhotosUI
import SwiftUI

/// The picture of a person, round; the first letters of the name when there is none.
struct Avatar: View {
    let id: String
    let name: String
    /// When the picture was set (see `SocialAccount.photo`): nil or 0, no picture.
    let photo: Double?
    var size: CGFloat = 34
    /// A ring around it, for the pins on the map.
    var ring: Color?

    @Environment(Social.self) private var social
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.deep
                Text(Avatars.initials(of: name))
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring ?? Theme.line, lineWidth: ring == nil ? 1 : max(2.5, size * 0.08)))
        .task(id: "\(id)-\(Int(photo ?? 0))") {
            image = await social.photo(of: id, version: photo ?? 0)
        }
        .accessibilityHidden(true)
    }
}

/// Your account: the picture your friends see, how you sign in, and the way out. Without an
/// account, the ways to make one.
struct ProfileView: View {
    @Environment(Social.self) private var social
    @State private var picked: PhotosPickerItem?
    @State private var deleting = false
    @State private var password = ""

    var body: some View {
        @Bindable var social = social
        ScrollView {
            VStack(spacing: 14) {
                ErrorBanner(error: $social.error)
                if let account = social.account {
                    VStack(spacing: 12) {
                        Avatar(id: account.id, name: account.name, photo: account.photo, size: 112)
                        Text(account.name).font(.display(.title3)).foregroundStyle(Theme.text)
                        Text(LocalizedStringKey(Self.kindLabel(account.kind))).font(.caption).foregroundStyle(Theme.sub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    Panel("Foto del profilo") {
                        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                            Label(LocalizedStringKey((account.photo ?? 0) > 0 ? "Cambia foto" : "Scegli una foto"), systemImage: "photo")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(social.busy)
                        if (account.photo ?? 0) > 0 {
                            Button { Task { await social.removePhoto() } } label: { Label("Togli la foto", systemImage: "trash") }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(social.busy)
                        }
                        Text("La vedono i tuoi amici: nella classifica, nell'elenco e sulla mappa quando condividi la posizione. Viene rimpicciolita prima di partire.")
                            .prose().font(.caption).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Panel("Account") {
                        InfoRow("Nome", account.name)
                        InfoRow("Amici", "\(social.friends.count)")
                        Button { Task { await social.signOut() } } label: { Label("Esci", systemImage: "rectangle.portrait.and.arrow.right") }
                            .buttonStyle(SecondaryButtonStyle())
                        Button { deleting = true } label: { Label("Elimina l'account", systemImage: "trash") }
                            .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
                    }
                } else {
                    SignInPanel()
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if social.busy {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let jpeg = Avatars.prepare(image) {
                    await social.setPhoto(jpeg)
                } else {
                    social.error = String(localized: "Non riesco a usare questa foto: provane un'altra.")
                }
                picked = nil
            }
        }
        .alert("Eliminare l'account?", isPresented: $deleting) {
            if social.account?.kind == nil || social.account?.kind == "password" {
                SecureField("Password", text: $password)
            }
            Button("Elimina", role: .destructive) {
                let typed = password
                password = ""
                Task {
                    let withPassword = social.account?.kind == nil || social.account?.kind == "password"
                    _ = await social.deleteAccount(password: withPassword ? typed : nil)
                }
            }
            Button("Annulla", role: .cancel) { password = "" }
        } message: {
            Text("Il nome, la foto, gli amici e i totali condivisi vengono cancellati dal server. Le giornate sul tuo iPhone restano.")
        }
    }

    static func kindLabel(_ kind: String?) -> String {
        switch kind {
        case "apple": "Accesso con Apple"
        case "google": "Accesso con Google"
        default: "Accesso con nome e password"
        }
    }
}

/// The ways into an account: with Apple, with Google, or with a name and a password.
struct SignInPanel: View {
    @Environment(Social.self) private var social
    @State private var name = ""
    @State private var password = ""
    @State private var new = true
    @State private var google = GoogleSignIn()

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
            Panel("Accesso rapido") {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    apple(result)
                }
                .signInWithAppleButtonStyle(Theme.dark ? .white : .black)
                .frame(height: 50)
                .clipShape(Capsule())
                .disabled(social.busy)
                if GoogleSignIn.clientID != nil {
                    Button {
                        Task {
                            do {
                                let token = try await google.token()
                                await social.enter(with: "google", token: token, name: nil)
                            } catch GoogleSignIn.Failure.canceled {
                                // Closed by hand: nothing to say.
                            } catch {
                                social.error = String(localized: "L'accesso non è riuscito. Riprova.")
                            }
                        }
                    } label: { Label("Continua con Google", systemImage: "g.circle.fill") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(social.busy)
                }
                Text("Al server arriva solo un identificativo e il nome da mostrare agli amici: niente email.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// What "Sign in with Apple" gave back: its token goes to the server, with the name the
    /// first time (Apple gives it only then).
    private func apple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                social.error = String(localized: "L'accesso non è riuscito. Riprova.")
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            Task { await social.enter(with: "apple", token: token, name: name) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            // The app installed from outside TestFlight is signed without this permission.
            social.error = String(localized: "Accedi con Apple funziona solo con l'app installata da TestFlight. Qui usa un nome e una password.")
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
