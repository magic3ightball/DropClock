import Foundation
import StoreKit

/// Freemium: 1 medication free, one-time purchase unlocks everything.
/// Create a Non-Consumable IAP with this product ID in App Store Connect.
///
/// FREE LAUNCH: `monetizationEnabled` is false, so everything is unlocked and StoreKit is never called.
/// To turn on payments later:
///   1. Finish Paid Apps Agreement + Korean tax info (BRN) in App Store Connect.
///   2. Set `monetizationEnabled = true`.
///   3. Set CURRENT_PROJECT_VERSION (build number) to `firstPaidBuild` or higher.
/// Anyone who first downloaded a build lower than `firstPaidBuild` keeps everything for free,
/// so early users are never downgraded.
@MainActor
final class UnlockStore: ObservableObject {
    static let monetizationEnabled = false
    static let firstPaidBuild = 1000

    static let productID = "com.magic3ightball.dropclock.unlock"
    static let freeMedicationLimit = 1

    @Published private(set) var isUnlocked = !UnlockStore.monetizationEnabled
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    func start() async {
        guard Self.monetizationEnabled else { isUnlocked = true; return }
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
        guard Self.monetizationEnabled else { isUnlocked = true; return }
        var unlocked = false
        // Grandfather users from the free-launch period.
        if let result = try? await AppTransaction.shared,
           case .verified(let app) = result,
           let originalBuild = Int(app.originalAppVersion),
           originalBuild < Self.firstPaidBuild {
            unlocked = true
        }
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
