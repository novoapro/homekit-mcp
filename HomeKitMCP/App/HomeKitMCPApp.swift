import SwiftUI

@main
struct HomeKitMCPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.homeKitViewModel)
                .environmentObject(appDelegate.logViewModel)
                .environmentObject(appDelegate.settingsViewModel)
        }
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case devices
    case logs
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .devices: return "Devices"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .devices: return "house.fill"
        case .logs: return "list.bullet.rectangle"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var homeKitViewModel: HomeKitViewModel
    @EnvironmentObject var logViewModel: LogViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State private var selection: NavigationItem = .devices

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                DeviceListView(viewModel: homeKitViewModel)
            }
            .tabItem {
                Label(NavigationItem.devices.label, systemImage: NavigationItem.devices.icon)
            }
            .tag(NavigationItem.devices)
            .badge(homeKitViewModel.totalDeviceCount)

            NavigationStack {
                LogViewerView(viewModel: logViewModel)
            }
            .tabItem {
                Label(NavigationItem.logs.label, systemImage: NavigationItem.logs.icon)
            }
            .tag(NavigationItem.logs)
            .badge(logViewModel.totalLogCount)

            NavigationStack {
                SettingsView(viewModel: settingsViewModel)
            }
            .tabItem {
                Label(NavigationItem.settings.label, systemImage: NavigationItem.settings.icon)
            }
            .tag(NavigationItem.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PreviewData.homeKitViewModel)
        .environmentObject(PreviewData.logViewModel)
        .environmentObject(PreviewData.settingsViewModel)
}

struct Theme {
    // MARK: - Colors
    
    struct Text {
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let tertiary = Color(uiColor: .tertiaryLabel)
    }
    
    struct Tint {
        static let main = Color.indigo // Modern primary color
        static let secondary = Color.purple
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
}

// Extension to support custom colors without Asset Catalog
extension Theme {
    static var mainBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }
    
    static var contentBackground: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }
    
    static var detailBackground: Color {
        Color(UIColor.tertiarySystemGroupedBackground)
    }
}
