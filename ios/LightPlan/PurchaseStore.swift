import Foundation
import Combine
import StoreKit

@MainActor final class PurchaseStore: ObservableObject {
    static var productID: String { AppConfiguration.productID }
    @Published private(set) var unlocked = false
    @Published private(set) var ready = false
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    @Published private(set) var loadingProduct = false
    @Published var messageKey: String?
    private var listener: Task<Void, Never>?
    func start() async {
        if listener == nil {
            listener = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled, let self else { return }
                    guard case .verified(let transaction) = result, transaction.productID == Self.productID else { continue }
                    await self.reloadEntitlements()
                    await transaction.finish()
                }
            }
        }
        await reloadEntitlements(); await loadProduct()
    }
    deinit { listener?.cancel() }
    func loadProduct() async {
        guard !loadingProduct else { return }
        loadingProduct = true; defer { loadingProduct = false }
        do {
            product = try await Product.products(for: [Self.productID]).first(where: { $0.id == Self.productID && $0.type == .nonConsumable })
            if product == nil { messageKey = "purchase.unavailable" }
            else if messageKey == "purchase.unavailable" { messageKey = nil }
        } catch { messageKey = "purchase.unavailable" }
    }
    func reloadEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID,
               transaction.productType == .nonConsumable, transaction.revocationDate == nil, !transaction.isUpgraded { found = true }
        }
        unlocked = found; ready = true // StoreKit-verified signed transactions, never a local premium flag.
    }
    func purchase() async {
        guard !busy, let product else { messageKey = "purchase.unavailable"; return }
        busy = true; messageKey = nil; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard transaction.productID == Self.productID, transaction.productType == .nonConsumable, transaction.revocationDate == nil else { messageKey = "purchase.unverified"; return }
                await reloadEntitlements(); await transaction.finish()
                messageKey = unlocked ? "purchase.success" : "purchase.unverified"
            case .success(.unverified): messageKey = "purchase.unverified"
            case .pending: messageKey = "purchase.pending"
            case .userCancelled: messageKey = nil // Cancellation is not an error or a successful purchase.
            @unknown default: messageKey = "purchase.unavailable"
            }
        } catch { messageKey = "purchase.unavailable" }
    }
    func restore() async {
        guard !busy else { return }
        busy = true; messageKey = nil; defer { busy = false }
        do { try await AppStore.sync(); await reloadEntitlements(); messageKey = unlocked ? "purchase.restored" : "purchase.none" }
        catch { messageKey = "purchase.unavailable" }
    }
}
