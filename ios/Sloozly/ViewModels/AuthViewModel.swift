import Foundation
@preconcurrency import FirebaseAuth
import Combine

// MARK: - Auth View Model

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var error: String?
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthStateListener()
    }
    
    isolated deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Auth State
    
    private func setupAuthStateListener() {
        authStateHandle = AuthService.shared.addAuthStateListener { [weak self] user in
            Task { @MainActor in
                if user != nil {
                    await self?.fetchCurrentUser()
                } else {
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                }
                self?.isLoading = false
            }
        }
    }
    
    private func fetchCurrentUser() async {
        do {
            // Refresh token first
            _ = try await AuthService.shared.refreshToken()
            
            // Fetch user from backend
            currentUser = try await APIService.shared.getMe()
            isAuthenticated = true
        } catch {
            // Token might be invalid, sign out
            try? AuthService.shared.signOut()
            isAuthenticated = false
            currentUser = nil
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        
        do {
            _ = try await AuthService.shared.signUp(email: email, password: password)
            await fetchCurrentUser()
        } catch {
            self.error = AuthError.from(error).localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        
        do {
            _ = try await AuthService.shared.signIn(email: email, password: password)
            await fetchCurrentUser()
        } catch {
            self.error = AuthError.from(error).localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        do {
            try AuthService.shared.signOut()
            isAuthenticated = false
            currentUser = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Password Reset
    
    func sendPasswordReset(email: String) async -> Bool {
        error = nil
        
        do {
            try await AuthService.shared.sendPasswordReset(email: email)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    // MARK: - Delete Account
    
    func deleteAccount() async -> Bool {
        isLoading = true
        error = nil
        
        do {
            try await AuthService.shared.deleteAccount()
            isAuthenticated = false
            currentUser = nil
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    // MARK: - Clear Error
    
    func clearError() {
        error = nil
    }
}
