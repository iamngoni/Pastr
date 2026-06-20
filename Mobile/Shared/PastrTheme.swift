import SwiftUI

enum PastrTheme {
    static let accent = Color(red: 0.02, green: 0.48, blue: 1.0)

    static func tint(_ name: PastrTintName) -> Color {
        switch name {
        case .blue:
            Color(red: 0.02, green: 0.48, blue: 1.0)
        case .mint:
            Color(red: 0.17, green: 0.72, blue: 0.45)
        case .violet:
            Color(red: 0.49, green: 0.33, blue: 0.92)
        case .amber:
            Color(red: 0.95, green: 0.58, blue: 0.18)
        case .graphite:
            Color(red: 0.39, green: 0.42, blue: 0.48)
        }
    }
}

