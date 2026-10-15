import SwiftUI

struct AlarmEditView: View {
    enum Mode {
        case create
        case edit(Alarm)
        
        var title: String {
            switch self {
            case .create: return "New Alarm"
            case .edit: return "Edit Alarm"
            }
        }
    }
    
    let mode: Mode
    let onSave: (Int, Int, String?, [Int]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTime = Date()
    @State private var label = ""
    @State private var selectedDays: Set<DayOfWeek> = []
    
    init(mode: Mode, onSave: @escaping (Int, Int, String?, [Int]) -> Void) {
        self.mode = mode
        self.onSave = onSave
        
        // Initialize state from existing alarm if editing
        if case .edit(let alarm) = mode {
            _label = State(initialValue: alarm.label ?? "")
            _selectedDays = State(initialValue: alarm.repeatDays.asDayOfWeekSet)
            
            // Set initial time
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            if let date = Calendar.current.date(from: components) {
                _selectedTime = State(initialValue: date)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Time Picker
                Section {
                    DatePicker(
                        "Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                
                // Label
                Section("Label") {
                    TextField("Alarm label (optional)", text: $label)
                }
                
                // Repeat Days
                Section("Repeat") {
                    ForEach(DayOfWeek.allCases, id: \.self) { day in
                        Button {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        } label: {
                            HStack {
                                Text(day.shortName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedDays.contains(day) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    // Quick select buttons
                    HStack(spacing: 12) {
                        Button("Weekdays") {
                            selectedDays = Set(DayOfWeek.weekdays)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Weekends") {
                            selectedDays = Set(DayOfWeek.weekends)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Every Day") {
                            selectedDays = Set(DayOfWeek.allCases)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        
                        Button("Clear") {
                            selectedDays = []
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
                
                // Penalty info
                Section {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.orange)
                        Text("Snooze penalty: $5.00")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Each snooze doubles the penalty. First snooze is $5, second is $10, third is $20, and so on.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAlarm()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveAlarm() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let labelValue = label.isEmpty ? nil : label
        
        onSave(hour, minute, labelValue, selectedDays.asIntArray)
    }
}

#Preview {
    AlarmEditView(mode: .create) { _, _, _, _ in }
}
