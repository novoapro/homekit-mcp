import SwiftUI

struct ProUpgradePrompt: View {
    let featureName: String
    let description: String
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 36))
                .foregroundColor(.yellow)

            Text("\(featureName) requires Pro")
                .font(.headline)
                .foregroundColor(Theme.Text.primary)

            Text(description)
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)
                .multilineTextAlignment(.center)

            Button(action: onSubscribe) {
                Label("Upgrade to Pro", systemImage: "crown.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.yellow.opacity(0.15))
                    .foregroundColor(.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(Theme.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
    }
}
