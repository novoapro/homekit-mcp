import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "1")
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutSettingsView()
    }
}
