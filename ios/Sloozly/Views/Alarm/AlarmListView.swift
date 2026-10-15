import SwiftUI

struct AlarmListView: View {
    @StateObject private var viewModel = AlarmViewModel()
    @State private var showAddAlarm = false
    @State private var selectedAlarm: Alarm?
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.alarms.isEmpty {
                    ProgressView("Loading alarms...")
                } else if viewModel.alarms.isEmpty {
                    EmptyAlarmView {
                        showAddAlarm = true
                    }
                } else {
                    alarmList
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
                await viewModel.fetchAlarms()
            }
            .refreshable {
                await viewModel.fetchAlarms()
            }
        }
    }
    
    private var alarmList: some View {
        List {
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
            }
            .onDelete { offsets in
                viewModel.deleteAlarm(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
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
    let alarm: Alarm
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
