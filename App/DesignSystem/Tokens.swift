import SwiftUI
import UIKit
import RunCoachCore

/// Palette de l'app. Chaque couleur a une variante claire et une sombre (ARCHITECTURE.md §7.1).
struct RCColors {
    let background = Color(light: 0xF4F5F7, dark: 0x0B0D10)
    let surface = Color(light: 0xFFFFFF, dark: 0x15181D)
    let surfaceRaised = Color(light: 0xEEF0F3, dark: 0x1E2228)
    let separator = Color(light: 0xE3E5EA, dark: 0x2A2F37)
    let textPrimary = Color(light: 0x0B0D10, dark: 0xF5F7FA)
    let textSecondary = Color(light: 0x5B6470, dark: 0x9AA3AF)
    /// Aplats uniquement : bouton principal, anneau, point du replay.
    let accent = Color(hex: 0xFF6A1F)
    /// Texte sombre sur l'orange : le blanc n'y atteint pas le contraste minimal.
    let onAccent = Color(hex: 0x0B0D10)
    /// Texte ou icône en couleur d'accent : assombri en mode clair pour le contraste.
    let accentText = Color(light: 0xC2410C, dark: 0xFF6A1F)
    let danger = Color(light: 0xD92D4B, dark: 0xF43F5E)
    /// Jaune et non orange, pour ne pas se confondre avec l'accent.
    let warning = Color(light: 0xA16207, dark: 0xFACC15)

    /// Zones de fréquence cardiaque, de 1 à 5 (mêmes familles de couleur que Garmin).
    func zone(_ number: Int) -> Color {
        switch number {
        case 1: return Color(hex: 0x8B95A5)
        case 2: return Color(hex: 0x3B82F6)
        case 3: return Color(hex: 0x10B981)
        case 4: return Color(hex: 0xF59E0B)
        default: return Color(hex: 0xEF4444)
        }
    }

    /// Nom des zones tel que Garmin les affiche.
    func zoneName(_ number: Int) -> String {
        ["Échauffement", "Facile", "Aérobie", "Seuil", "Maximum"][max(1, min(5, number)) - 1]
    }
}

extension Color {
    static let rc = RCColors()

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

extension WorkoutKind {
    var color: Color {
        switch self {
        case .easy: return Color(hex: 0x34D399)
        case .long: return Color(hex: 0x60A5FA)
        case .tempo: return Color(hex: 0xF59E0B)
        case .intervals: return Color(hex: 0xF43F5E)
        case .recovery: return Color(hex: 0x2DD4BF)
        case .strength: return Color(hex: 0xA78BFA)
        case .race: return Color(hex: 0xFF6A1F)
        }
    }

    var icon: String {
        switch self {
        case .easy: return "figure.run"
        case .long: return "road.lanes"
        case .tempo: return "speedometer"
        case .intervals: return "bolt.fill"
        case .recovery: return "leaf.fill"
        case .strength: return "dumbbell.fill"
        case .race: return "flag.checkered"
        }
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let card: CGFloat = 24
    static let inner: CGFloat = 14
}

extension Animation {
    static let rcStandard = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

extension View {
    /// Carte standard : fond `surface`, coins arrondis continus.
    func rcCard(padding: CGFloat = Spacing.l) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rc.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    func rcScreenBackground() -> some View {
        self.background(Color.rc.background.ignoresSafeArea())
    }
}
