import Foundation
import StoreKit
import Combine
import UIKit

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, Sendable {
    case free
    case pro
}

// MARK: - Subscription Service

@MainActor
class SubscriptionService: ObservableObject {

    static let productIds: Set<String> = [
        "com.mnplab.compai_home.pro.monthly",
        "com.mnplab.compai_home.pro.yearly"
    ]

    @Published var currentTier: SubscriptionTier = .free {
        didSet {
            defaults.set(currentTier.rawValue, forKey: Keys.cachedTier)
            if currentTier != oldValue {
                tierChangedSubject.send(currentTier)
            }
        }
    }
    @Published var availableProducts: [Product] = []
    @Published var purchaseInProgress = false
    @Published var subscriptionExpirationDate: Date? {
        didSet {
            if let date = subscriptionExpirationDate {
                defaults.set(date.timeIntervalSince1970, forKey: Keys.cachedExpiration)
            } else {
                defaults.removeObject(forKey: Keys.cachedExpiration)
            }
        }
    }
    @Published var isInGracePeriod = false
    @Published var activeProductId: String?
    @Published var lastError: String?

    /// Published when the subscription tier changes. MCPServer subscribes to broadcast via WebSocket.
    let tierChangedSubject = PassthroughSubject<SubscriptionTier, Never>()

    private let defaults = UserDefaults.standard
    private var transactionListener: Task<Void, Never>?

    private enum Keys {
        static let cachedTier = "subscription.cachedTier"
        static let cachedExpiration = "subscription.cachedExpiration"
        /// Set via: `defaults write com.mnplab.compai-home subscription.debugOverrideTier pro`
        /// Remove: `defaults delete com.mnplab.compai-home subscription.debugOverrideTier`
        static let debugOverrideTier = "subscription.debugOverrideTier"
    }

    init() {
        // Load cached tier for instant startup reads
        let cached = defaults.string(forKey: Keys.cachedTier) ?? SubscriptionTier.free.rawValue
        self.currentTier = SubscriptionTier(rawValue: cached) ?? .free
        let cachedExp = defaults.double(forKey: Keys.cachedExpiration)
        if cachedExp > 0 {
            self.subscriptionExpirationDate = Date(timeIntervalSince1970: cachedExp)
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshSubscriptionStatus()
                }
            }
        }

        Task {
            await loadProducts()
            await refreshSubscriptionStatus()
        }

        // Re-check subscription status when the app returns to the foreground
        // to catch revocations, expirations, and external changes.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshSubscriptionStatus()
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.productIds)
            self.availableProducts = products.sorted { $0.price < $1.price }
        } catch {
            AppLogger.server.error("Failed to load products: \(error.localizedDescription)")
            self.lastError = "Failed to load subscription products."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        purchaseInProgress = true
        lastError = nil
        defer { purchaseInProgress = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await refreshSubscriptionStatus()
                AppLogger.server.info("Purchase successful: \(product.id)")
            case .unverified(_, let error):
                lastError = "Purchase verification failed."
                AppLogger.server.error("Purchase unverified: \(error.localizedDescription)")
            }
        case .userCancelled:
            AppLogger.server.info("Purchase cancelled by user")
        case .pending:
            lastError = "Purchase is pending approval."
            AppLogger.server.info("Purchase pending")
        @unknown default:
            lastError = "Unknown purchase result."
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
        } catch {
            lastError = "Failed to restore purchases."
            AppLogger.server.error("Restore purchases failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Status

    func refreshSubscriptionStatus() async {
        #if DEBUG
        if let override = defaults.string(forKey: Keys.debugOverrideTier),
           let tier = SubscriptionTier(rawValue: override) {
            self.currentTier = tier
            return
        }
        #endif

        var foundPro = false
        var latestExpiration: Date?
        var gracePeriod = false
        var activeProduct: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIds.contains(transaction.productID) else { continue }

            if transaction.revocationDate != nil {
                continue
            }

            foundPro = true
            activeProduct = transaction.productID

            if let expiration = transaction.expirationDate {
                if latestExpiration == nil || expiration > latestExpiration! {
                    latestExpiration = expiration
                    activeProduct = transaction.productID
                }
                if expiration < Date() {
                    gracePeriod = true
                }
            }
        }

        self.currentTier = foundPro ? .pro : .free
        self.activeProductId = activeProduct
        self.subscriptionExpirationDate = latestExpiration
        self.isInGracePeriod = gracePeriod
    }

    // MARK: - Nonisolated Reader

    /// Thread-safe reader from UserDefaults cache.
    /// Safe to call from NIO event loops (MCPServer guard functions).
    nonisolated func readCurrentTier() -> SubscriptionTier {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: Keys.debugOverrideTier),
           let tier = SubscriptionTier(rawValue: override) {
            return tier
        }
        #endif
        let raw = UserDefaults.standard.string(forKey: Keys.cachedTier) ?? SubscriptionTier.free.rawValue
        return SubscriptionTier(rawValue: raw) ?? .free
    }
}
