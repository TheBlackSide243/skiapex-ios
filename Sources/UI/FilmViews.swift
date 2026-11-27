import AVKit
import SwiftUI

/// The film of a day: made when the sheet opens, played, and sent.
struct FilmSheet: View {
    let day: SkiDay
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var player: AVPlayer?
    /// The last frame, shown while the film is being made.
    @State private var still: UIImage?
    @State private var progress = 0.0
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(DayFilm.size.width / DayFilm.size.height, contentMode: .fit)
                        .clipShape(Theme.round)
                        .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                        .accessibilityLabel(Text("Video della giornata: la traccia che si disegna sulla mappa con i numeri"))
                } else if failed {
                    Text("Non riesco a creare il video di questa giornata.")
                        .prose().font(.subheadline).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                    Button { Task { await make() } } label: { Label("Riprova", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    if let still {
                        Image(uiImage: still)
                            .resizable().scaledToFit()
                            .clipShape(Theme.round)
                            .overlay(Theme.round.strokeBorder(Theme.line, lineWidth: 1))
                            .opacity(0.55)
                            .accessibilityHidden(true)
                    }
                    ProgressView(value: progress).tint(Theme.accent).frame(maxWidth: 220)
                    Text("Preparo il video…").font(.subheadline).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
                if let file {
                    ShareLink(item: file) { Label("Condividi il video", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Video della giornata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            .task { await make() }
            .onDisappear { player?.pause() }
        }
        .modifier(Dressed())
    }

    @MainActor private func make() async {
        guard file == nil else { return }
        failed = false
        progress = 0
        if still == nil { still = DayFilm.still(day) }
        do {
            let made = try await DayFilm.make(day) { done in
                Task { @MainActor in progress = done }
            }
            file = made
            let player = AVPlayer(url: made)
            self.player = player
            player.play()
        } catch is CancellationError {
            // The sheet was closed while it was being made.
        } catch {
            failed = true
        }
    }
}
