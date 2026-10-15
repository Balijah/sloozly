import Foundation
@preconcurrency import FirebaseAuth

// MARK: - Auth Service

@MainActor
final class AuthService {
    static let shared = AuthService()
    
    private init() {}
    
    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }
    
    var isSignedIn: Bool {
        currentUser != nil
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        // Get ID token for backend registration
        let token = try await result.user.getIDToken()
        
        // Register with backend
        _ = try await APIService.shared.register(firebaseToken: token)
        
        // Store token
        KeychainManager.shared.authToken = token
        KeychainManager.shared.userId = result.user.uid
        
        return result.user
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        
        // Get fresh ID token
        let token = try await result.user.getIDToken()
        
        // Store token
        KeychainManager.shared.authToken = token
        KeychainManager.shared.userId = result.user.uid
        
        return result.user
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
        
        // Clear stored credentials
        KeychainManager.shared.authToken = nil
        KeychainManager.shared.userId = nil
    }
    
    // MARK: - Refresh Token
    
    func refreshToken() async throws -> String {
        guard let user = currentUser else {
            throw AuthError.notSignedIn
        }
        
        let token = try await user.getIDToken(forcingRefresh: true)
        KeychainManager.shared.authToken = token
        
        return token
    }
    
    // MARK: - Password Reset
    
    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
    
    // MARK: - Delete Account
    
    func deleteAccount() async throws {
        guard let user = currentUser else {
            throw AuthError.notSignedIn
        }
        
        // Delete from backend first
        try await APIService.shared.deleteAccount()
        
        // Then delete from Firebase
        try await user.delete()
        
        // Clear local storage
        KeychainManager.shared.authToken = nil
        KeychainManager.shared.userId = nil
    }
    
    // MARK: - Update Email
    
    func updateEmail(to newEmail: String) async throws {
        guard let user = currentUser else {
            throw AuthError.notSignedIn
        }
        
        try await user.sendEmailVerification(beforeUpdatingEmail: newEmail)
    }
    
    // MARK: - Update Password
    
    func updatePassword(to newPassword: String) async throws {
        guard let user = currentUser else {
            throw AuthError.notSignedIn
        }
        
        try await user.updatePassword(to: newPassword)
    }
    
    // MARK: - Re-authenticate (required for sensitive operations)
    
    func reauthenticate(email: String, password: String) async throws {
        guard let user = currentUser else {
            throw AuthError.notSignedIn
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)
    }
    
    // MARK: - Auth State Listener
    
    func addAuthStateListener(_ listener: @escaping (FirebaseAuth.User?) -> Void) -> AuthStateDidChangeListenerHandle {
        return Auth.auth().addStateDidChangeListener { _, user in
            listener(user)
        }
    }
    
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notSignedIn
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkError
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to continue"
        case .invalidCredentials:
            return "Invalid email or password"
        case .emailAlreadyInUse:
            return "This email is already registered"
        case .weakPassword:
            return "Password must be at least 6 characters"
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
    
    static func from(_ error: Error) -> AuthError {
        let nsError = error as NSError
        
        if nsError.domain == AuthErrorDomain {
            switch nsError.code {
            case AuthErrorCode.invalidEmail.rawValue,
                 AuthErrorCode.wrongPassword.rawValue,
                 AuthErrorCode.userNotFound.rawValue:
                return .invalidCredentials
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                return .emailAlreadyInUse
            case AuthErrorCode.weakPassword.rawValue:
                return .weakPassword
            case AuthErrorCode.networkError.rawValue:
                return .networkError
            default:
                return .unknown(error.localizedDescription)
            }
        }
        
        return .unknown(error.localizedDescription)
    }
}
