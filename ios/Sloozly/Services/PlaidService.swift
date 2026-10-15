import Foundation
import LinkKit

// MARK: - Plaid Service

final class PlaidService {
    static let shared = PlaidService()
    
    private var linkHandler: Handler?
    
    private init() {}
    
    // MARK: - Start Link Flow
    
    func startLinkFlow(
        from presentingViewController: UIViewController,
        onSuccess: @escaping (String, String) -> Void, // publicToken, accountId
        onExit: @escaping (LinkKit.LinkError?) -> Void
    ) {
        Task {
            do {
                // Get link token from backend
                let linkToken = try await APIService.shared.createLinkToken()
                
                await MainActor.run {
                    presentPlaidLink(
                        linkToken: linkToken,
                        from: presentingViewController,
                        onSuccess: onSuccess,
                        onExit: onExit
                    )
                }
            } catch {
                await MainActor.run {
                    onExit(nil)
                }
            }
        }
    }
    
    private func presentPlaidLink(
        linkToken: String,
        from presentingViewController: UIViewController,
        onSuccess: @escaping (String, String) -> Void,
        onExit: @escaping (LinkKit.LinkError?) -> Void
    ) {
        // Create link configuration
        var linkConfiguration = LinkTokenConfiguration(
            token: linkToken,
            onSuccess: { linkSuccess in
                // Extract public token and account ID
                let publicToken = linkSuccess.publicToken
                
                // Get the first account (user should only select one)
                if let account = linkSuccess.metadata.accounts.first {
                    onSuccess(publicToken, account.id)
                } else {
                    onExit(nil)
                }
            }
        )
        
        linkConfiguration.onExit = { linkExit in
            onExit(linkExit.error)
        }
        
        // Create handler
        let result = Plaid.create(linkConfiguration)
        
        switch result {
        case .success(let handler):
            self.linkHandler = handler
            handler.open(presentUsing: .viewController(presentingViewController))
            
        case .failure(let error):
            print("Failed to create Plaid handler: \(error.localizedDescription)")
            onExit(nil)
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        linkHandler = nil
    }
}

// MARK: - Plaid Link Result

struct PlaidLinkResult {
    let publicToken: String
    let accountId: String
    let institutionName: String?
    let accountName: String?
    let accountMask: String?
}
