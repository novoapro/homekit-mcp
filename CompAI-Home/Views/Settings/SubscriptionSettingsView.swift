import SwiftUI
import StoreKit

struct SubscriptionSettingsView: View {
    @ObservedObject var subscriptionService: SubscriptionService

    var body: some View {
        Form {
            // Current Status
            Section {
                HStack {
                    Text("Current Plan")
                    Spacer()
                    Text(subscriptionService.currentTier == .pro ? "Pro" : "Free")
                        .foregroundColor(subscriptionService.currentTier == .pro ? Theme.Status.active : Theme.Text.secondary)
                        .fontWeight(.medium)
                }

                if subscriptionService.currentTier == .pro, let expiration = subscriptionService.subscriptionExpirationDate {
                    HStack {
                        Text("Renews")
                        Spacer()
                        Text(expiration, style: .date)
                            .foregroundColor(Theme.Text.secondary)
                    }

                    if subscriptionService.isInGracePeriod {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Billing issue — update payment method to keep Pro features.")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                    }
                }
            } header: {
                Text("Subscription Status")
            }

            // Pro Features
            if subscriptionService.currentTier == .free {
                Section {
                    proFeatureRow(icon: "bolt.fill", color: .orange, title: "Automation+", description: "Create powerful automations with triggers, conditions, and actions")
                    proFeatureRow(icon: "sparkles", color: .purple, title: "AI Assistant", description: "Generate and improve automations with AI")
                    proFeatureRow(icon: "globe", color: .blue, title: "Web Dashboard", description: "Full automation management from any browser")
                } header: {
                    Text("Pro Features")
                }
            }

            // Products
            if !subscriptionService.availableProducts.isEmpty {
                Section {
                    ForEach(subscriptionService.availableProducts, id: \.id) { product in
                        let isActive = subscriptionService.activeProductId == product.id
                        Button {
                            Task {
                                try? await subscriptionService.purchase(product)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isActive {
                                    Image(systemName: "crown.fill")
                                        .foregroundColor(.yellow)
                                        .font(.body)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                        .foregroundColor(Theme.Text.primary)
                                        .fontWeight(.medium)
                                    Text(product.description)
                                        .font(.footnote)
                                        .foregroundColor(Theme.Text.secondary)
                                }
                                Spacer()
                                if isActive {
                                    Text("Active")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(Theme.Status.active)
                                } else {
                                    Text(product.displayPrice)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .disabled(subscriptionService.purchaseInProgress || isActive)
                    }

                    if subscriptionService.purchaseInProgress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.footnote)
                                .foregroundColor(Theme.Text.secondary)
                        }
                    }
                } header: {
                    Text(subscriptionService.currentTier == .pro ? "Change Plan" : "Subscribe")
                }
            }

            // Manage
            Section {
                Button("Restore Purchases") {
                    Task {
                        await subscriptionService.restorePurchases()
                    }
                }

                if subscriptionService.currentTier == .pro {
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                }
            }

            if let error = subscriptionService.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Subscription")
    }

    private func proFeatureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(Theme.Text.primary)
                Text(description)
                    .font(.footnote)
                    .foregroundColor(Theme.Text.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
