import Foundation
import UIKit
import Combine

// MARK: - Bank View Model

@MainActor
final class BankViewModel: ObservableObject {
    @Published var isLinked = false
    @Published var bankAccount: BankAccountInfo?
    @Published var isLoading = false
    @Published var isLinking = false
    @Published var error: String?
    @Published var successMessage: String?
    
    // MARK: - Fetch Status
    
    func fetchBankStatus() async {
        isLoading = true
        error = nil
        
        do {
            let response = try await APIService.shared.getBankStatus()
            isLinked = response.linked
            bankAccount = response.account
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Link Bank Account
    
    func linkBankAccount(from viewController: UIViewController) {
        isLinking = true
        error = nil
        successMessage = nil
        
        PlaidService.shared.startLinkFlow(
            from: viewController,
            onSuccess: { [weak self] publicToken, accountId in
                Task { @MainActor in
                    await self?.exchangeToken(publicToken: publicToken, accountId: accountId)
                }
            },
            onExit: { [weak self] linkError in
                Task { @MainActor in
                    self?.isLinking = false
                    if let error = linkError {
                        self?.error = error.localizedDescription
                    }
                }
            }
        )
    }
    
    private func exchangeToken(publicToken: String, accountId: String) async {
        do {
            let account = try await APIService.shared.exchangeBankToken(
                publicToken: publicToken,
                accountId: accountId
            )
            
            isLinked = true
            bankAccount = account
            successMessage = "Bank account linked successfully!"
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLinking = false
        PlaidService.shared.cleanup()
    }
    
    // MARK: - Unlink Bank Account
    
    func unlinkBankAccount() async -> Bool {
        isLoading = true
        error = nil
        successMessage = nil
        
        do {
            try await APIService.shared.unlinkBank()
            
            isLinked = false
            bankAccount = nil
            successMessage = "Bank account unlinked"
            isLoading = false
            
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    // MARK: - Clear Messages
    
    func clearError() {
        error = nil
    }
    
    func clearSuccess() {
        successMessage = nil
    }
}
