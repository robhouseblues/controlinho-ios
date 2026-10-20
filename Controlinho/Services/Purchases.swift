import Foundation
import Observation
import StoreKit
import SwiftUI

/// Controlinho Plus: a one-time purchase that allows more than one TV and removes the ads.
@MainActor
@Observable
final class Purchases {
    static let plusID = "com.tsikadatech.controlinho.plus"

    private static let ownedKey = "hasPlus"

    /// Remembered between launches, so Plus owners don't see an ad flash in before
    /// StoreKit has answered.
    private(set) var hasPlus = UserDefaults.standard.bool(forKey: ownedKey) {
        didSet { UserDefaults.standard.set(hasPlus, forKey: Self.ownedKey) }
    }
    /// Whether StoreKit has answered at least once since launch.
    private(set) var hasChecked = false
    private(set) var product: Product?
    private(set) var isWorking = false
    /// What went wrong (or is pending) with the last purchase or restore.
    private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // Purchases made outside the app (Ask to Buy approvals, refunds, other devices).
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.plusID]).first
    }

    /// Reads whether this Apple Account (or its family) owns Plus.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.plusID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        #if DEBUG
        // Lets the simulator show the Plus version without a StoreKit setup: -debugPlus YES
        if UserDefaults.standard.bool(forKey: "debugPlus") { owned = true }
        #endif
        hasPlus = owned
        hasChecked = true
    }

    /// Runs a purchase through SwiftUI's `purchase` action, which shows the App Store sheet.
    func buy(using purchase: PurchaseAction) async {
        guard let product, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            switch try await purchase(product) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                hasPlus = true
            case .success(.unverified):
                message = "The App Store couldn't confirm the purchase. Try Restore purchases."
            case .pending:
                message = "Your purchase is waiting for approval. Plus turns on as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. Check your connection and try again."
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            message = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        await refresh()
        if !hasPlus { message = "No Plus purchase was found for this Apple Account." }
    }
}
