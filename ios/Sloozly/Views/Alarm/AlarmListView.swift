import SwiftUI
import AlarmKit

struct AlarmListView: View {
    @StateObject private var viewModel = AlarmViewModel()
    @StateObject private var alarmKitManager = AlarmKitManager.shared
    @StateObject private var snoozeQueue = SnoozeEventQueue.shared
    @State private var showAddAlarm = false
    @State private var selectedAlarm: AlarmModel?
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.alarms.isEmpty {
                    ProgressView("Loading alarms...")
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            authorizationBanner
                            pendingPenaltiesBanner
                            
                            if viewModel.alarms.isEmpty {
                                EmptyAlarmView {
                                    showAddAlarm = true
                                }
                                .padding(.top, 40)
                            } else {
                                alarmList
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddAlarm) {
                AlarmEditView(mode: .create) { hour, minute, label, repeatDays in
                    Task {
                        let success = await viewModel.createAlarm(
                            hour: hour,
                            minute: minute,
                            label: label,
                            repeatDays: repeatDays
                        )
                        if success {
                            showAddAlarm = false
                        }
                    }
                }
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmEditView(mode: .edit(alarm)) { hour, minute, label, repeatDays in
                    Task {
                        let success = await viewModel.updateAlarm(
                            alarm,
                            hour: hour,
                            minute: minute,
                            label: label,
                            repeatDays: repeatDays
                        )
                        if success {
                            selectedAlarm = nil
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.error ?? "")
            }
            .task {
                alarmKitManager.startAuthorizationObservation()
                await viewModel.fetchAlarms()
                await snoozeQueue.processQueue()
            }
            .refreshable {
                await viewModel.fetchAlarms()
                await snoozeQueue.processQueue()
            }
        }
    }
    
    // MARK: - Authorization Banner
    
    @ViewBuilder
    private var authorizationBanner: some View {
        switch alarmKitManager.authorizationState {
        case .denied:
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alarms Disabled")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Enable alarms in Settings > Sloozly to ring through silent mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
        case .notDetermined:
            Button {
                Task {
                    await alarmKitManager.requestAuthorization()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "alarm.waves.left.and.right")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Alarm Alerts")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Allow Sloozly to ring through silent mode and Focus.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            
        case .authorized:
            EmptyView()
            
        @unknown default:
            EmptyView()
        }
    }
    
    // MARK: - Pending Penalties Banner
    
    @ViewBuilder
    private var pendingPenaltiesBanner: some View {
        if snoozeQueue.hasPendingEvents {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snoozeQueue.pendingCount) penalty(ies) pending")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Will be sent when connection is restored.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Retry") {
                    Task { await snoozeQueue.processQueue() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
        }
        
        if let result = snoozeQueue.lastPenaltyResult {
            HStack(spacing: 12) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.succeeded ? .green : .red)
                
                VStack(alignment: .leading, spacing: 2) {
                    if result.succeeded, let resp = result.response {
                        Text("Snooze #\(result.snoozeNumber): \(resp.amountFormatted)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(resp.status.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = result.error {
                        Text("Penalty failed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                (result.succeeded ? Color.green : Color.red).opacity(0.1)
            )
            .cornerRadius(12)
        }
    }
    
    // MARK: - Alarm List
    
    private var alarmList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.alarms) { alarm in
                AlarmRowView(alarm: alarm) {
                    Task {
                        await viewModel.toggleAlarm(alarm)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedAlarm = alarm
                }
                .padding(.vertical, 8)
                
                Divider()
            }
        }
    }
}

// MARK: - Empty State

struct EmptyAlarmView: View {
    let onAddAlarm: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "alarm")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Alarms")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first alarm to start waking up on time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onAddAlarm()
            } label: {
                Label("Add Alarm", systemImage: "plus")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Alarm Row

struct AlarmRowView: View {
    let alarm: AlarmModel
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 8) {
                    if let label = alarm.label, !label.isEmpty {
                        Text(label)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(alarm.repeatDaysText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if alarm.isEnabled, let timeUntil = alarm.timeUntilNextAlarm {
                    Text("in \(timeUntil)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                
                Text(alarm.penaltyAmountFormatted)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AlarmListView()
}
