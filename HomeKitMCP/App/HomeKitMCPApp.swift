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
                .environmentObject(appDelegate.workflowViewModel)
                .tint(Theme.Tint.main)
        }
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case devices
    case workflows
    case logs
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .devices: return "Devices"
        case .workflows: return "Workflows"
        case .logs: return "Logs"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .devices: return "house.fill"
        case .workflows: return "bolt.fill"
        case .logs: return "list.bullet.rectangle"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var homeKitViewModel: HomeKitViewModel
    @EnvironmentObject var logViewModel: LogViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var workflowViewModel: WorkflowViewModel

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
                WorkflowListView(
                    viewModel: workflowViewModel,
                    aiWorkflowService: settingsViewModel.aiWorkflowService,
                    aiEnabled: settingsViewModel.aiEnabled && settingsViewModel.aiApiKeyConfigured
                )
            }
            .tabItem {
                Label(NavigationItem.workflows.label, systemImage: NavigationItem.workflows.icon)
            }
            .tag(NavigationItem.workflows)
            .badge(workflowViewModel.enabledCount)

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
        .background(Theme.mainBackground)
    }
}

#Preview {
    ContentView()
        .environmentObject(PreviewData.homeKitViewModel)
        .environmentObject(PreviewData.logViewModel)
        .environmentObject(PreviewData.settingsViewModel)
        .environmentObject(PreviewData.workflowViewModel)
}


