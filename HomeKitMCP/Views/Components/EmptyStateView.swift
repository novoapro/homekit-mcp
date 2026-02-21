import SwiftUI

/// Reusable empty state view matching Apple Home app's clean, centered style.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var iconColor: Color = .secondary
    var actions: [EmptyStateAction] = []

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(iconColor.opacity(0.6))
                .padding(.bottom, 4)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(Theme.Text.primary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if !actions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button(action: action.handler) {
                            Label(action.title, systemImage: action.icon)
                                .foregroundColor(action.iconColor)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(action.tint ?? Theme.Tint.main)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var iconColor: Color? = nil
    var tint: Color?
    let handler: () -> Void
}

#Preview {
    EmptyStateView(
        icon: "house",
        title: "No HomeKit devices found",
        message: "Make sure you have devices set up in the Home app.",
        actions: [
            EmptyStateAction(title: "Create Workflow", icon: "plus", iconColor: Color.white) {},
            EmptyStateAction(title: "AI Builder", icon: "sparkles", iconColor: Color.white, tint: Color.purple) {}
        ]
    )
}
