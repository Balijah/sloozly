import Foundation
import Combine

// MARK: - Alarm View Model

@MainActor
final class AlarmViewModel: ObservableObject {
    @Published var alarms: [AlarmModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let alarmKitManager = AlarmKitManager.shared
    
    // MARK: - Fetch Alarms
    
    func fetchAlarms() async {
        isLoading = true
        error = nil
        
        do {
            alarms = try await APIService.shared.listAlarms()
            
            // Schedule all enabled alarms via AlarmKit
            for alarm in alarms where alarm.isEnabled {
                await alarmKitManager.scheduleAlarm(alarm)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Create Alarm
    
    func createAlarm(hour: Int, minute: Int, label: String? = nil, repeatDays: [Int] = []) async -> Bool {
        error = nil
        
        let request = CreateAlarmRequest(
            hour: hour,
            minute: minute,
            label: label,
            isEnabled: true,
            repeatDays: repeatDays
        )
        
        do {
            let alarm = try await APIService.shared.createAlarm(request)
            alarms.append(alarm)
            alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            
            await alarmKitManager.scheduleAlarm(alarm)
            
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    // MARK: - Update Alarm
    
    func updateAlarm(_ alarm: AlarmModel, hour: Int? = nil, minute: Int? = nil, label: String? = nil, isEnabled: Bool? = nil, repeatDays: [Int]? = nil, skipPenalty: Bool? = nil) async -> Bool {
        error = nil
        
        let request = UpdateAlarmRequest(
            hour: hour,
            minute: minute,
            label: label,
            isEnabled: isEnabled,
            repeatDays: repeatDays,
            skipPenalty: skipPenalty
        )
        
        do {
            let updatedAlarm = try await APIService.shared.updateAlarm(id: alarm.id, request)
            
            if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[index] = updatedAlarm
            }
            alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            
            if updatedAlarm.isEnabled {
                await alarmKitManager.scheduleAlarm(updatedAlarm)
            } else {
                await alarmKitManager.cancelAlarm(updatedAlarm)
            }
            
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    // MARK: - Toggle Alarm
    
    func toggleAlarm(_ alarm: AlarmModel) async {
        _ = await updateAlarm(alarm, isEnabled: !alarm.isEnabled)
    }
    
    // MARK: - Delete Alarm
    
    func deleteAlarm(_ alarm: AlarmModel) async -> Bool {
        error = nil
        
        do {
            try await APIService.shared.deleteAlarm(id: alarm.id)
            
            alarms.removeAll { $0.id == alarm.id }
            await alarmKitManager.cancelAlarm(alarm)
            
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    
    // MARK: - Delete Alarm at Index (for swipe to delete)
    
    func deleteAlarm(at offsets: IndexSet) {
        for index in offsets {
            let alarm = alarms[index]
            Task {
                await deleteAlarm(alarm)
            }
        }
    }
    
    // MARK: - Clear Error
    
    func clearError() {
        error = nil
    }
}
