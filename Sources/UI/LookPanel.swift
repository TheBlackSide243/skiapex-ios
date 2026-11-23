import SwiftUI
import UIKit

/// The colors of the app and its icon on the Home Screen, to choose in Settings.
struct LookPanel: View {
    /// The icon in use, as iOS names it: nil for the one the app comes with.
    @State private var icon = UIApplication.shared.alternateIconName
    @State private var error: String?

    var body: some View {
        let current = Looks.shared.look
        Panel("Aspetto") {
            ErrorBanner(error: $error)
            Text("Tema").font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Look.allCases) { look in
                    Button { Looks.shared.choose(look) } label: { LookSwatch(look: look, chosen: look == current) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(Text(LocalizedStringKey(look.label)))
                        .accessibilityAddTraits(look == current ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: current)
            if UIApplication.shared.supportsAlternateIcons {
                Divider().overlay(Theme.line)
                Text("Icona dell'app").font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Look.allCases) { look in
                            Button { setIcon(look) } label: { IconChoice(look: look, chosen: look.iconName == icon) }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel(Text(LocalizedStringKey(look.label)))
                                .accessibilityAddTraits(look.iconName == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("L'icona cambia sulla schermata Home: iOS te lo conferma con un avviso.")
                    .prose().font(.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setIcon(_ look: Look) {
        guard look.iconName != icon else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(look.iconName)
                icon = look.iconName
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A look in small: its page, a card on it, a line of words and its accent.
private struct LookSwatch: View {
    let look: Look
    let chosen: Bool

    var body: some View {
        let colors = look.palette
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(colors.text).frame(width: 30, height: 5)
                Capsule().fill(colors.sub).frame(width: 44, height: 4)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Capsule().fill(colors.accent).frame(width: 34, height: 12)
                    Circle().fill(colors.lift).frame(width: 12, height: 12)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 62)
            .background(colors.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(6)
            .background(colors.bg, in: Theme.roundSmall)
            .overlay(Theme.roundSmall.strokeBorder(chosen ? Theme.accent : Theme.line, lineWidth: chosen ? 2.5 : 1))
            HStack(spacing: 4) {
                if chosen {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                }
                Text(LocalizedStringKey(look.label)).font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Theme.text : Theme.sub).lineLimit(1)
            }
        }
    }
}

/// An icon of the app to choose, with the name of its look.
private struct IconChoice: View {
    let look: Look
    let chosen: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 6) {
            Image(look.iconPreview)
                .resizable()
                .frame(width: 62, height: 62)
                .clipShape(shape)
                .overlay(shape.strokeBorder(chosen ? Theme.accent : Theme.line, lineWidth: chosen ? 2.5 : 1))
            Text(LocalizedStringKey(look.label)).font(.caption2.weight(chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? Theme.text : Theme.sub).lineLimit(1)
        }
    }
}
