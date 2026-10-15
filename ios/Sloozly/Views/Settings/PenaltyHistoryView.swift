import SwiftUI

struct PenaltyHistoryView: View {
    @StateObject private var viewModel = PenaltyViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.penalties.isEmpty {
                    ProgressView("Loading history...")
                } else if viewModel.penalties.isEmpty {
                    EmptyHistoryView()
                } else {
                    historyContent
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.refreshAll()
            }
            .refreshable {
                await viewModel.refreshAll()
            }
        }
    }
    
    private var historyContent: some View {
        List {
            // Stats Summary
            if let stats = viewModel.stats {
                Section {
                    StatsSummaryView(stats: stats)
                }
            }
            
            // Penalty List
            Section("Recent Penalties") {
                ForEach(viewModel.penalties) { penalty in
                    PenaltyRowView(penalty: penalty)
                        .task {
                            await viewModel.loadMoreIfNeeded(currentItem: penalty)
                        }
                }
                
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Stats Summary

struct StatsSummaryView: View {
    let stats: PenaltyStats
    
    var body: some View {
        VStack(spacing: 16) {
            // Main stat
            VStack(spacing: 4) {
                Text(stats.lifetime.totalAmountFormatted)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                
                Text("Total Penalties")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Secondary stats
            HStack(spacing: 24) {
                VStack {
                    Text("\(stats.lifetime.totalPenalties)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Snoozes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(stats.lifetime.averageAmountFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(stats.last7Days.amountFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("This Week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Penalty Row

struct PenaltyRowView: View {
    let penalty: Penalty
    
    var body: some View {
        HStack {
            // Status icon
            Image(systemName: penalty.status.iconName)
                .foregroundColor(statusColor)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(penalty.displayTitle)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("Snooze #\(penalty.snoozeNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(penalty.triggeredAt.relativeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if penalty.status == .failed, let reason = penalty.failureReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(penalty.amountFormatted)
                    .font(.headline)
                    .foregroundColor(penalty.status == .completed ? .primary : .secondary)
                
                Text(penalty.status.displayText)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch penalty.status {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Empty State

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("No Penalties Yet!")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("You haven't hit snooze yet. Keep up the good work!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

#Preview {
    PenaltyHistoryView()
}
