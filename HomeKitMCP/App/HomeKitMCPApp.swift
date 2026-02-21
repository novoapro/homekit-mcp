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

// MARK: - Navigation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
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

/// Sidebar items for category-based filtering (matching Apple Home app Categories section)
enum SidebarCategory: String, CaseIterable, Identifiable, Hashable {
    case lights
    case climate
    case security
    case fans
    case switches
    case sensors
    case doors

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lights: return "Lights"
        case .climate: return "Climate"
        case .security: return "Security"
        case .fans: return "Fans"
        case .switches: return "Switches"
        case .sensors: return "Sensors"
        case .doors: return "Doors & Windows"
        }
    }

    var icon: String {
        switch self {
        case .lights: return "lightbulb.fill"
        case .climate: return "thermometer"
        case .security: return "lock.fill"
        case .fans: return "fan.fill"
        case .switches: return "switch.2"
        case .sensors: return "sensor"
        case .doors: return "door.left.hand.closed"
        }
    }

    var color: Color {
        switch self {
        case .lights: return Theme.Category.light
        case .climate: return Theme.Category.climate
        case .security: return Theme.Category.security
        case .fans: return Theme.Category.fan
        case .switches: return Theme.Category.switchOutlet
        case .sensors: return Theme.Category.sensor
        case .doors: return Theme.Category.door
        }
    }

    /// HomeKit category types that match this sidebar category.
    /// Uses the actual string values returned by HMAccessoryCategory.categoryType at runtime.
    var matchingCategoryTypes: Set<String> {
        switch self {
        case .lights:
            return ["HMAccessoryCategoryTypeLightbulb"]
        case .climate:
            return [
                "HMAccessoryCategoryTypeThermostat",
                "HMAccessoryCategoryTypeAirConditioner",
                "HMAccessoryCategoryTypeAirHeater",
                "HMAccessoryCategoryTypeAirPurifier",
                "HMAccessoryCategoryTypeAirHumidifier",
                "HMAccessoryCategoryTypeAirDehumidifier",
                "HMAccessoryCategoryTypeFaucet",
                "HMAccessoryCategoryTypeShowerHead",
                "HMAccessoryCategoryTypeSprinkler"
            ]
        case .security:
            // Note: HomeKit uses "DoorLock", not "Lock"
            return ["HMAccessoryCategoryTypeDoorLock", "HMAccessoryCategoryTypeSecuritySystem"]
        case .fans:
            return ["HMAccessoryCategoryTypeFan"]
        case .switches:
            return ["HMAccessoryCategoryTypeSwitch", "HMAccessoryCategoryTypeProgrammableSwitch", "HMAccessoryCategoryTypeOutlet"]
        case .sensors:
            return ["HMAccessoryCategoryTypeSensor"]
        case .doors:
            return [
                "HMAccessoryCategoryTypeDoor",
                "HMAccessoryCategoryTypeWindow",
                "HMAccessoryCategoryTypeWindowCovering",
                "HMAccessoryCategoryTypeGarageDoorOpener"
            ]
        }
    }
}

/// Represents what the sidebar has selected
enum SidebarSelection: Hashable {
    case nav(NavigationItem)
    case category(SidebarCategory)
    case room(String)
}

// MARK: - Content View (Sidebar Navigation)

struct ContentView: View {
    @EnvironmentObject var homeKitViewModel: HomeKitViewModel
    @EnvironmentObject var logViewModel: LogViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var workflowViewModel: WorkflowViewModel

    @State private var selection: SidebarSelection? = .nav(.devices)

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .background(Theme.mainBackground)
        .onChange(of: settingsViewModel.workflowsEnabled) { enabled in
            if !enabled && selection == .nav(.workflows) {
                selection = .nav(.devices)
            }
        }
        // Keyboard shortcuts for sidebar navigation (Cmd+1/2/3, Cmd+, for Settings)
        .background {
            VStack {
                Button("") { selection = .nav(.devices) }
                    .keyboardShortcut("1", modifiers: .command)
                if settingsViewModel.workflowsEnabled {
                    Button("") { selection = .nav(.workflows) }
                        .keyboardShortcut("2", modifiers: .command)
                }
                Button("") { selection = .nav(.logs) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selection = .nav(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .hidden()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            // App branding
            HStack(spacing: 14) {
                Image("SidebarLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 70)
                VStack(alignment: .leading, spacing: 0) {
                    Text("HomeKit")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Text.primary)
                    Text("MCP")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Text.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.gray)

            // Main navigation items
            Section {
                ForEach(NavigationItem.allCases.filter { item in
                    if item == .workflows { return settingsViewModel.workflowsEnabled }
                    return true
                }) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(SidebarSelection.nav(item))
                }
            }

            // Rooms section (matching Home app sidebar)
            if !homeKitViewModel.availableRooms.isEmpty {
                Section("Rooms") {
                    ForEach(homeKitViewModel.availableRooms, id: \.self) { room in
                        Label(room, systemImage: "house")
                            .tag(SidebarSelection.room(room))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .nav(.devices), .none:
            NavigationStack {
                DeviceListView(viewModel: homeKitViewModel)
            }
        case .nav(.workflows):
            NavigationStack {
                WorkflowListView(
                    viewModel: workflowViewModel,
                    aiWorkflowService: settingsViewModel.aiWorkflowService,
                    aiEnabled: settingsViewModel.aiEnabled && settingsViewModel.aiApiKeyConfigured
                )
            }
        case .nav(.logs):
            NavigationStack {
                LogViewerView(viewModel: logViewModel, onCancelExecution: { executionId in
                    workflowViewModel.cancelExecution(executionId: executionId)
                })
            }
        case .nav(.settings):
            NavigationStack {
                SettingsView(viewModel: settingsViewModel)
            }
        case .category(let category):
            NavigationStack {
                DeviceListView(
                    viewModel: homeKitViewModel,
                    initialCategoryFilter: category,
                    onFiltersCleared: { selection = .nav(.devices) }
                )
            }
            .id(category) // Force recreation when category changes
        case .room(let room):
            NavigationStack {
                DeviceListView(
                    viewModel: homeKitViewModel,
                    initialRoomFilter: room,
                    onFiltersCleared: { selection = .nav(.devices) }
                )
            }
            .id(room) // Force recreation when room changes
        }
    }

}

#Preview {
    ContentView()
        .environmentObject(PreviewData.homeKitViewModel)
        .environmentObject(PreviewData.logViewModel)
        .environmentObject(PreviewData.settingsViewModel)
        .environmentObject(PreviewData.workflowViewModel)
}
