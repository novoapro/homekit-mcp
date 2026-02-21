import SwiftUI

struct Theme {
    // MARK: - Text Colors

    struct Text {
        static let primary = Color.dynamic(light: "#121212ff", dark: "#ffffffd9")
        static let secondary = Color.dynamic(light: "#121212d3", dark: "#ffffff99")
        static let tertiary = Color.dynamic(light: "#121212a0", dark: "#ffffff4d")
    }

    // MARK: - Tint Colors

    struct Tint {
        static let main = Color.orange
        static let secondary = Color.teal
    }

    // MARK: - Status Colors

    struct Status {
        static let active = Color.green
        static let inactive = Color.gray
        static let error = Color.red
        static let warning = Color.orange
    }

    // MARK: - Category Colors (matching Apple Home app)

    struct Category {
        static let light = Color(hex: "#FFB800")        // Warm yellow/gold — lights, outlets
        static let climate = Color(hex: "#5AC8FA")       // Light blue — thermostats, HVAC
        static let security = Color(hex: "#30B0C7")      // Teal — locks, cameras, security systems
        static let switchOutlet = Color(hex: "#34C759")   // Green — switches, outlets, programmable switches
        static let fan = Color(hex: "#5AC8FA")           // Light blue — fans (same as climate)
        static let media = Color(hex: "#8E8E93")         // Gray — speakers, TVs
        static let sensor = Color(hex: "#FF9F0A")        // Orange — sensors
        static let door = Color(hex: "#30B0C7")          // Teal — doors, garage doors, windows
        static let general = Color(hex: "#8E8E93")       // Gray — fallback for unknown types

        /// Returns the Home-app-style category color for a given HMAccessoryCategoryType string.
        static func color(for categoryType: String) -> Color {
            switch categoryType {
            case "HMAccessoryCategoryTypeLightbulb":
                return light
            case "HMAccessoryCategoryTypeSwitch",
                 "HMAccessoryCategoryTypeProgrammableSwitch":
                return switchOutlet
            case "HMAccessoryCategoryTypeOutlet":
                return switchOutlet
            case "HMAccessoryCategoryTypeThermostat":
                return climate
            case "HMAccessoryCategoryTypeFan":
                return fan
            case "HMAccessoryCategoryTypeDoor",
                 "HMAccessoryCategoryTypeWindow",
                 "HMAccessoryCategoryTypeGarageDoorOpener":
                return door
            case "HMAccessoryCategoryTypeDoorLock":
                return security
            case "HMAccessoryCategoryTypeSensor":
                return sensor
            case "HMAccessoryCategoryTypeSecuritySystem":
                return security
            case "HMAccessoryCategoryTypeBridge":
                return general
            default:
                return general
            }
        }
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

    // MARK: - Semantic Colors

    struct Colors {
        static let pill = Color.dynamic(light: "#e8e8edff", dark: "#3a3a3cff")
        static let chipInactive = Color(UIColor.systemGray6)
    }

    // MARK: - Animations

    struct Animation {
        static let expand = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let filter = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}

// MARK: - Background & Surface Hierarchy

extension Theme {
    /// Primary background — matches Apple Home app's system grouped background.
    static var mainBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    /// Content card surface — for list rows, cards, tiles.
    static var contentBackground: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }

    /// Detail/nested surface — for characteristic tiles, nested content.
    static var detailBackground: Color {
        Color(UIColor.tertiarySystemGroupedBackground)
    }

    /// Tile surface — for device tiles and cards.
    static var tileSurface: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }

    /// Surface overlay — for nested tiles within expanded content.
    static var surfaceOverlay: Color {
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
