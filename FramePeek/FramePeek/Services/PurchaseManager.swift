import Foundation
import StoreKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private enum TimeoutError: Error {
    case timedOut
}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }
        
        guard let result = try await group.next() else {
            throw TimeoutError.timedOut
        }
        
        group.cancelAll()
        return result
    }
}

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
    private var pendingPurchaseTransaction: StoreKit.Transaction?
    private var finishedTransactionIDs: Set<UInt64> = []
    private var currentPurchaseTask: Task<Void, Never>?
    
    private init() {
        loadPurchaseState()
        startTransactionListener()
        Task {
            await loadProductPrice()
        }
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
            for await result in StoreKit.Transaction.currentEntitlements {
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
        // Cancel any existing purchase task
        currentPurchaseTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        pendingPurchaseTransaction = nil
        
        defer {
            // Always reset loading state
            isLoading = false
            currentPurchaseTask = nil
        }
        
        do {
            // Load product with timeout
            let products: [Product]
            do {
                products = try await withTimeout(seconds: 10) {
                    try await Product.products(for: [self.productId])
                }
            } catch {
                if error is TimeoutError {
                    errorMessage = String(localized: "Unable to connect to App Store. Please check your internet connection and try again.")
                } else {
                    errorMessage = String(format: String(localized: "Failed to load product: %@"), error.localizedDescription)
                }
                return
            }
            
            guard let product = products.first else {
                errorMessage = String(localized: "Product not available. Please ensure the app is properly configured.")
                return
            }
            
            // Update price if available
            productPrice = product.displayPrice
            
            // Check if purchase was already completed by listener
            if isPurchased {
                return
            }
            
            // Ensure we're presenting from the main window to avoid NSRemoteView issues
            // when called from within a SwiftUI sheet. This must happen before purchase()
            #if canImport(AppKit)
            // Activate the app and bring main window to front
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // Find and activate the main window
            if let mainWindow = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first(where: { $0.isMainWindow || $0.isKeyWindow }) {
                mainWindow.makeKeyAndOrderFront(nil)
                mainWindow.level = .normal
            }
            #endif
            
            // Small delay to ensure window activation is complete
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check if purchase was already completed by listener
            if isPurchased {
                return
            }
            
            // Call purchase - this will show the Apple IAP dialog
            // StoreKit will present from the main window automatically
            let result: Product.PurchaseResult
            do {
                result = try await product.purchase()
            } catch {
                // Check if purchase was completed by transaction listener while we were waiting
                if isPurchased {
                    // Purchase completed successfully via listener, just return
                    return
                }
                
                if error is CancellationError {
                    // User cancelled - don't show error
                    return
                } else {
                    let errorDesc = error.localizedDescription
                    // Check if this is a payment sheet dismissal error
                    if errorDesc.contains("Payment sheet dismissed") || errorDesc.contains("Payment Sheet Failed") {
                        // Payment sheet was dismissed - this is expected when user cancels
                        return
                    }
                    errorMessage = String(format: String(localized: "Purchase failed: %@"), errorDesc)
                }
                return
            }
            
            // Check if purchase was already completed by listener
            if isPurchased {
                return
            }
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Mark this transaction as pending so the listener knows we're handling it
                    pendingPurchaseTransaction = transaction
                    let transactionID = transaction.id
                    
                    // Only finish if we haven't already finished this transaction
                    // This handles the case where the listener might have already processed it
                    if !finishedTransactionIDs.contains(transactionID) {
                        // Deliver content first, then finish the transaction
                        savePurchaseState(true)
                        await transaction.finish()
                        finishedTransactionIDs.insert(transactionID)
                    } else {
                        // Transaction was already finished by listener, just update state
                        savePurchaseState(true)
                    }
                    
                    // Clear pending transaction after handling
                    pendingPurchaseTransaction = nil
                case .unverified(_, let error):
                    errorMessage = String(localized: "Purchase verification failed")
                    print("Purchase verification failed: \(error)")
                    pendingPurchaseTransaction = nil
                }
            case .userCancelled:
                // User cancelled in the Apple dialog - don't show error
                pendingPurchaseTransaction = nil
                return
            case .pending:
                errorMessage = String(localized: "Purchase is pending approval")
                // Don't clear pending transaction - it will be handled when it completes
            @unknown default:
                errorMessage = String(localized: "Unknown purchase result")
                pendingPurchaseTransaction = nil
            }
        } catch {
            // Check if this is a payment sheet dismissal error (which is expected when cancelled)
            let errorDesc = error.localizedDescription
            if errorDesc.contains("Payment sheet dismissed") || errorDesc.contains("Payment Sheet Failed") {
                // Payment sheet was dismissed - this is expected when user cancels
                // Don't show error, just return
                return
            }
            
            // If purchase was completed by listener, ignore the error
            if !isPurchased {
                errorMessage = String(format: String(localized: "Purchase failed: %@"), errorDesc)
            }
        }
    }
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        // In StoreKit 2, we check current entitlements directly
        // AppStore.sync() is not needed - the transaction listener handles updates
        var foundPurchase = false
        
        // Check current entitlements with timeout protection
        // Use a task to iterate the async sequence with a timeout
        do {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                // Task to check entitlements
                group.addTask {
                    for await result in StoreKit.Transaction.currentEntitlements {
                        if case .verified(let transaction) = result {
                            if transaction.productID == self.productId {
                                // Found a valid purchase
                                // Finish the transaction if we haven't already
                                let transactionID = transaction.id
                                
                                // Check if already finished on MainActor
                                let alreadyFinished = await MainActor.run {
                                    self.finishedTransactionIDs.contains(transactionID)
                                }
                                
                                if !alreadyFinished {
                                    await transaction.finish()
                                    _ = await MainActor.run {
                                        self.finishedTransactionIDs.insert(transactionID)
                                    }
                                }
                                
                                // Update purchase state
                                await MainActor.run {
                                    self.savePurchaseState(true)
                                }
                                return true
                            }
                        }
                    }
                    return false
                }
                
                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
                    throw TimeoutError.timedOut
                }
                
                // Wait for first task to complete
                if let result = try await group.next() {
                    foundPurchase = result
                    group.cancelAll()
                }
            }
        } catch {
            if error is TimeoutError {
                errorMessage = String(localized: "Restore timed out. Please check your internet connection and try again.")
                return
            } else {
                // If timeout fails, still check if we found a purchase
                print("Restore entitlements check failed: \(error.localizedDescription)")
            }
        }
        
        // If we didn't find a purchase in entitlements, show message
        if !foundPurchase && !isPurchased {
            errorMessage = String(localized: "No previous purchases found. If you've purchased this item, it may take a few moments to restore.")
        } else if foundPurchase {
            // Purchase was found and restored
            errorMessage = nil
        }
    }
    
    private func startTransactionListener() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self = self else { break }
                
                switch result {
                case .verified(let transaction):
                    if transaction.productID == self.productId {
                        let transactionID = transaction.id
                        
                        await MainActor.run {
                            // Check if this transaction is already being handled by purchase()
                            if let pending = self.pendingPurchaseTransaction,
                               pending.id == transactionID {
                                // Transaction is already being handled by purchase() method
                                // The purchase() method will finish it, so we just update state if needed
                                if !self.isPurchased {
                                    self.savePurchaseState(true)
                                }
                                if self.isLoading {
                                    self.isLoading = false
                                }
                                return
                            }
                            
                            // Only finish if we haven't already finished this transaction
                            // This handles restores, family sharing, and other transaction updates
                            if !self.finishedTransactionIDs.contains(transactionID) {
                                // Deliver content first, then finish the transaction
                                self.savePurchaseState(true)
                                
                                // Finish transaction asynchronously (finish() is async)
                                Task {
                                    await transaction.finish()
                                    await MainActor.run {
                                        self.finishedTransactionIDs.insert(transactionID)
                                        
                                        // If purchase is in progress, complete it
                                        if self.isLoading {
                                            self.isLoading = false
                                        }
                                    }
                                }
                            } else {
                                // Transaction already finished, just update state
                                self.savePurchaseState(true)
                                if self.isLoading {
                                    self.isLoading = false
                                }
                            }
                        }
                    }
                case .unverified:
                    // Unverified transactions should not be processed
                    break
                }
            }
        }
    }
}

