import Foundation
import StoreKit
import SwiftUI

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published var isPurchased: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var productPrice: String?
    
    private let productId = "framepeek.premium"
    private let purchaseStateKey = "isPurchased"
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        loadPurchaseState()
        startTransactionListener()
        Task {
            await loadProductPrice()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    private func loadPurchaseState() {
        // Load cached state from UserDefaults (for performance)
        // StoreKit is the source of truth and will verify on app launch
        isPurchased = UserDefaults.standard.bool(forKey: purchaseStateKey)
        
        // Verify with StoreKit (handles purchase restoration automatically)
        Task {
            await checkPurchaseStatus()
        }
    }
    
    private func savePurchaseState(_ purchased: Bool) {
        isPurchased = purchased
        // Cache in UserDefaults for performance (StoreKit is the source of truth)
        UserDefaults.standard.set(purchased, forKey: purchaseStateKey)
        UserDefaults.standard.synchronize()
    }
    
    func loadProductPrice() async {
        do {
            let products = try await Product.products(for: [productId])
            if let product = products.first {
                productPrice = product.displayPrice
            }
        } catch {
            // Silently fail - network issues shouldn't block the app
            print("Failed to load product price: \(error)")
        }
    }
    
    func checkPurchaseStatus() async {
        guard !isPurchased else { return }
        
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                return
            }
            
            // Update price if available
            productPrice = product.displayPrice
            
            // Check current entitlements
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    if transaction.productID == productId {
                        savePurchaseState(true)
                        return
                    }
                }
            }
        } catch {
            // Silently fail - network issues shouldn't block the app
            print("Failed to check purchase status: \(error)")
        }
    }
    
    func purchase() async {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                errorMessage = String(localized: "Product not available")
                return
            }
            
            // Update price if available
            productPrice = product.displayPrice
            
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    savePurchaseState(true)
                case .unverified(_, let error):
                    errorMessage = String(localized: "Purchase verification failed")
                    print("Purchase verification failed: \(error)")
                }
            case .userCancelled:
                // User cancelled - don't show error
                break
            case .pending:
                errorMessage = String(localized: "Purchase is pending approval")
            @unknown default:
                errorMessage = String(localized: "Unknown purchase result")
            }
        } catch {
            let errorDesc = error.localizedDescription
            errorMessage = String(format: String(localized: "Purchase failed: %@"), errorDesc)
        }
    }
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            try await AppStore.sync()
            await checkPurchaseStatus()
            
            if !isPurchased {
                errorMessage = String(localized: "No previous purchases found")
            }
        } catch {
            let errorDesc = error.localizedDescription
            errorMessage = String(format: String(localized: "Failed to restore purchases: %@"), errorDesc)
        }
    }
    
    private func startTransactionListener() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { break }
                
                switch result {
                case .verified(let transaction):
                    if transaction.productID == self.productId {
                        await transaction.finish()
                        await MainActor.run {
                            self.savePurchaseState(true)
                        }
                    }
                case .unverified:
                    break
                }
            }
        }
    }
}

