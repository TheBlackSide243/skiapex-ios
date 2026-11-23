import MapKit
import SwiftUI

/// A friend on the map: the first letters of the name, ringed in the color of what they are doing.
struct FriendMarker: View {
    let friend: LiveFriend

    static func color(_ phase: String) -> Color {
        switch phase {
        case "run": Theme.accent
        case "lift": Theme.lift
        default: Theme.sub
        }
    }

    var body: some View {
        Text(friend.initials)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.text)
            .frame(width: 34, height: 34)
            .background(Theme.deep, in: Circle())
            .overlay(Circle().strokeBorder(Self.color(friend.phase), lineWidth: 3))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .accessibilityLabel(Text(friend.name))
    }
}

/// The friends skiing now who share where they are, on a map and one by one; and the switch to
/// share your own position while a day is recorded.
struct LiveFriendsPanel: View {
    @Environment(Social.self) private var social
    @AppStorage(Prefs.shareLive) private var sharing = false
    @AppStorage(Prefs.mapLook) private var mapLook = MapLook.standard.rawValue

    private var look: MapLook { MapLook(rawValue: mapLook) ?? .standard }

    var body: some View {
        let friends = social.live.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Panel("In diretta") {
            Toggle(isOn: $sharing) {
                Text("Fatti vedere dagli amici mentre registri").font(.subheadline).foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: sharing) { _, on in
                // Off: what the server has is taken back at once.
                if !on { Task { await social.stopSharing() } }
            }
            Text("Acceso, mentre registri una giornata i tuoi amici vedono dove sei. Il server tiene solo l'ultima posizione, non la salva, e la dimentica dieci minuti dopo l'ultimo aggiornamento, o subito quando metti in pausa o finisci.")
                .prose().font(.caption).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            if friends.isEmpty {
                Text("Nessun amico sta sciando in questo momento.").font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
            } else {
                Map(initialPosition: region(friends)) {
                    ForEach(friends) { friend in
                        Annotation(friend.name, coordinate: friend.coordinate) { FriendMarker(friend: friend) }
                    }
                }
                .mapStyle(look.style)
                .frame(height: 240)
                .clipShape(Theme.roundSmall)
                .overlay(Theme.roundSmall.strokeBorder(Theme.line, lineWidth: 1))
                // Drawn again when someone starts or stops, to keep everyone in view.
                .id(friends.map(\.id).joined(separator: ","))
                ForEach(friends) { friend in
                    HStack(spacing: 12) {
                        FriendMarker(friend: friend)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friend.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(friend.phaseLabel)).foregroundStyle(FriendMarker.color(friend.phase))
                                Text("·").foregroundStyle(Theme.sub)
                                Text(friend.date, style: .relative).foregroundStyle(Theme.sub)
                            }
                            .font(.caption)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(Fmt.speed(friend.speed)).font(.display(.subheadline)).monospacedDigit().foregroundStyle(Theme.text)
                            Text(Fmt.height(friend.alt)).font(.caption).foregroundStyle(Theme.sub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        // Asked again every half minute, while this is on screen.
        .task(id: social.account?.id) {
            while !Task.isCancelled {
                await social.loadLive()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Everyone in view, with room around: never closer than a couple of kilometers.
    private func region(_ friends: [LiveFriend]) -> MapCameraPosition {
        let lats = friends.map(\.lat), lons = friends.map(\.lon)
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return .automatic }
        let center = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.03, (north - south) * 1.8), longitudeDelta: max(0.04, (east - west) * 1.8))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
