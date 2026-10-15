import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var bankViewModel = BankViewModel()
    
    @State private var showDeleteConfirmation = false
    @State private var showUnlinkConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    if let user = authViewModel.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(user.displayName ?? "User")
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Bank Account Section
                Section("Payment") {
                    if bankViewModel.isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundColor(.secondary)
                        }
                    } else if bankViewModel.isLinked, let account = bankViewModel.bankAccount {
                        // Linked bank account
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading) {
                                Text(account.institutionName)
                                    .font(.headline)
                                Text("\(account.accountName) ••••\(account.accountMask)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(account.status.displayText)
                                .font(.caption)
                                .foregroundColor(account.status.isHealthy ? .green : .orange)
                        }
                        
                        Button(role: .destructive) {
                            showUnlinkConfirmation = true
                        } label: {
                            Label("Unlink Bank Account", systemImage: "xmark.circle")
                        }
                    } else {
                        // No bank linked
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No bank account linked")
                                .font(.headline)
                            Text("Link your bank account to enable snooze penalties")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            linkBankAccount()
                        } label: {
                            Label("Link Bank Account", systemImage: "plus.circle")
                        }
                    }
                }
                
                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0 (MVP)")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://sloozly.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    
                    Link(destination: URL(string: "https://sloozly.com/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }
                
                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await bankViewModel.fetchBankStatus()
            }
            .alert("Unlink Bank Account?", isPresented: $showUnlinkConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Unlink", role: .destructive) {
                    Task {
                        await bankViewModel.unlinkBankAccount()
                    }
                }
            } message: {
                Text("You won't be able to use snooze penalties until you link a new bank account.")
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await authViewModel.deleteAccount()
                    }
                }
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
            .alert("Error", isPresented: .constant(bankViewModel.error != nil)) {
                Button("OK") {
                    bankViewModel.clearError()
                }
            } message: {
                Text(bankViewModel.error ?? "")
            }
        }
    }
    
    private func linkBankAccount() {
        // Get the root view controller to present Plaid Link
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // Find the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        bankViewModel.linkBankAccount(from: topVC)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
