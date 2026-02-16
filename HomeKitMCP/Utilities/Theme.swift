import SwiftUI

struct Theme {
    // MARK: - Colors
    
    struct Text {
        static let primary = Color.dynamic(light: "#121212ff", dark: "#ffdc5eff")
        static let secondary = Color.dynamic(light: "#121212d3", dark: "#ffdc5ebc")
        static let tertiary = Color.dynamic(light: "#121212a0", dark: "#ffdc5ebc")
    }
    
    struct Tint {
        static let main = Color.orange // Modern primary color
        static let secondary = Color.teal
    }
    
    struct Status {
        static let active = Color.green
        static let inactive = Color.gray
        static let error = Color.red
        static let warning = Color.orange
    }
    
    // MARK: - Layout
    
    struct Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }
    
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }
    
    struct Colors {
        static let pill = Color.dynamic(light: "#f0f7d7ff", dark: "#FFFFFFFF")
    }
}

// Extension to support custom colors without Asset Catalog
extension Theme {
    static var mainBackground: Color {
        Color.dynamic(light: "#fff6d4ff", dark: "#000000")
    }
    
    static var contentBackground: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }
    
    static var detailBackground: Color {
        Color(UIColor.tertiarySystemGroupedBackground)
    }
}

// MARK: - Helper for HEX Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RGBA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    /// Creates a dynamic color that adapts to Light and Dark mode
    static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traitCollection in
            let hex = traitCollection.userInterfaceStyle == .dark ? dark : light
            return UIColor(hex: hex)
        })
    }
}

// Helper specific to UIColor for the dynamic provider
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: CGFloat(a)/255)
    }
}
