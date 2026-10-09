import Foundation
import StoreKit

/// Freemium: 1 medication free, one-time purchase unlocks everything.
/// Create a Non-Consumable IAP with this product ID in App Store Connect.
@MainActor
final class UnlockStore: ObservableObject {
    static let productID = "com.magic3ightball.dropclock.unlock"
    static let freeMedicationLimit = 1

    @Published private(set) var isUnlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    func start() async {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        product = try? await Product.products(for: [Self.productID]).first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    func purchase() async {
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        if case .success(let verification)? = try? await product.purchase(),
           case .verified(let transaction) = verification {
            await transaction.finish()
            isUnlocked = true
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func canAddMedication(currentCount: Int) -> Bool {
        isUnlocked || currentCount < Self.freeMedicationLimit
    }
}
