import Foundation
import Combine

// MARK: - Penalty View Model

@MainActor
final class PenaltyViewModel: ObservableObject {
    @Published var penalties: [Penalty] = []
    @Published var stats: PenaltyStats?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    
    private var currentPage = 1
    private var totalPages = 1
    private let pageSize = 20
    
    var hasMorePages: Bool {
        currentPage < totalPages
    }
    
    // MARK: - Fetch History
    
    func fetchHistory(refresh: Bool = false) async {
        if refresh {
            currentPage = 1
            penalties = []
        }
        
        isLoading = penalties.isEmpty
        error = nil
        
        do {
            let response = try await APIService.shared.getPenaltyHistory(
                page: currentPage,
                limit: pageSize
            )
            
            penalties = response.penalties
            totalPages = response.pagination.totalPages
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Load More
    
    func loadMoreIfNeeded(currentItem: Penalty?) async {
        guard let currentItem = currentItem,
              hasMorePages,
              !isLoadingMore else {
            return
        }
        
        // Check if we're near the end
        let thresholdIndex = penalties.index(penalties.endIndex, offsetBy: -5)
        guard let itemIndex = penalties.firstIndex(where: { $0.id == currentItem.id }),
              itemIndex >= thresholdIndex else {
            return
        }
        
        await loadNextPage()
    }
    
    private func loadNextPage() async {
        isLoadingMore = true
        currentPage += 1
        
        do {
            let response = try await APIService.shared.getPenaltyHistory(
                page: currentPage,
                limit: pageSize
            )
            
            penalties.append(contentsOf: response.penalties)
            totalPages = response.pagination.totalPages
            
        } catch {
            currentPage -= 1 // Revert on failure
            self.error = error.localizedDescription
        }
        
        isLoadingMore = false
    }
    
    // MARK: - Fetch Stats
    
    func fetchStats() async {
        do {
            stats = try await APIService.shared.getPenaltyStats()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Refresh All
    
    func refreshAll() async {
        async let historyTask: () = fetchHistory(refresh: true)
        async let statsTask: () = fetchStats()
        
        _ = await (historyTask, statsTask)
    }
    
    // MARK: - Clear Error
    
    func clearError() {
        error = nil
    }
}
