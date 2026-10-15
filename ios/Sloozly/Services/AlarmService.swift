import Foundation
import UserNotifications
import AVFoundation

// MARK: - Alarm Service

final class AlarmService {
    static let shared = AlarmService()
    
    private var audioPlayer: AVAudioPlayer?
    private var snoozeCounters: [String: Int] = [:] // alarmId: snoozeCount
    
    private init() {
        setupNotificationCategories()
        setupNotificationObservers()
    }
    
    // MARK: - Notification Setup
    
    private func setupNotificationCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: Constants.NotificationIdentifiers.snoozeAction,
            title: "Snooze ($5)",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: Constants.NotificationIdentifiers.dismissAction,
            title: "I'm Up!",
            options: [.destructive]
        )
        
        let category = UNNotificationCategory(
            identifier: Constants.NotificationIdentifiers.alarmCategory,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSnooze(_:)),
            name: .alarmSnoozed,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismiss(_:)),
            name: .alarmDismissed,
            object: nil
        )
    }
    
    // MARK: - Schedule Alarm
    
    func scheduleAlarm(_ alarm: Alarm) {
        guard alarm.isEnabled else {
            cancelAlarm(alarm)
            return
        }
        
        // Cancel existing notifications for this alarm
        cancelAlarm(alarm)
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = alarm.label ?? "Wake Up!"
        content.body = "Snooze costs \(alarm.penaltyAmountFormatted). Are you ready to get up?"
        content.sound = .defaultCritical
        content.categoryIdentifier = Constants.NotificationIdentifiers.alarmCategory
        content.userInfo = [
            "alarmId": alarm.id
        ]
        
        // Create trigger
        var dateComponents = DateComponents()
        dateComponents.hour = alarm.hour
        dateComponents.minute = alarm.minute
        
        if alarm.repeatDays.isEmpty {
            // One-time alarm
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: alarm.id,
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to schedule alarm: \(error.localizedDescription)")
                }
            }
        } else {
            // Repeating alarm - schedule for each day
            for day in alarm.repeatDays {
                var dayComponents = dateComponents
                dayComponents.weekday = day + 1 // Calendar uses 1-indexed weekdays (1 = Sunday)
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dayComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(alarm.id)-\(day)",
                    content: content,
                    trigger: trigger
                )
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Failed to schedule alarm for day \(day): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        print("Alarm scheduled: \(alarm.id) at \(alarm.timeString)")
    }
    
    // MARK: - Cancel Alarm
    
    func cancelAlarm(_ alarm: Alarm) {
        var identifiers = [alarm.id]
        
        // Also cancel day-specific notifications
        for day in 0...6 {
            identifiers.append("\(alarm.id)-\(day)")
        }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        
        // Reset snooze counter
        snoozeCounters.removeValue(forKey: alarm.id)
        
        print("Alarm cancelled: \(alarm.id)")
    }
    
    // MARK: - Snooze Handling
    
    @objc private func handleSnooze(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let alarmId = userInfo["alarmId"] as? String else {
            return
        }
        
        Task {
            await processSnooze(alarmId: alarmId)
        }
    }
    
    private func processSnooze(alarmId: String) async {
        // Increment snooze counter
        let currentCount = snoozeCounters[alarmId, default: 0] + 1
        snoozeCounters[alarmId] = currentCount
        
        print("Snooze #\(currentCount) for alarm: \(alarmId)")
        
        // Trigger penalty via API
        do {
            let response = try await APIService.shared.triggerPenalty(
                alarmId: alarmId,
                occurrenceId: "\(alarmId)_\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))",
                snoozeNumber: currentCount
            )
            
            print("Penalty triggered: \(response.amountFormatted)")
            
            // Show local notification about penalty
            showPenaltyNotification(amount: response.amountFormatted, snoozeNumber: currentCount)
            
        } catch {
            print("Failed to trigger penalty: \(error.localizedDescription)")
            // Still schedule the snooze alarm even if penalty fails
        }
        
        // Schedule snooze alarm (9 minutes from now)
        scheduleSnoozeAlarm(alarmId: alarmId, snoozeNumber: currentCount)
    }
    
    private func scheduleSnoozeAlarm(alarmId: String, snoozeNumber: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Snooze Over!"
        content.body = "Time to wake up! Next snooze will cost more."
        content.sound = .defaultCritical
        content.categoryIdentifier = Constants.NotificationIdentifiers.alarmCategory
        content.userInfo = [
            "alarmId": alarmId,
            "snoozeNumber": snoozeNumber
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(Constants.defaultSnoozeDurationMinutes * 60),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "\(alarmId)-snooze-\(snoozeNumber)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func showPenaltyNotification(amount: String, snoozeNumber: Int) {
        let content = UNMutableNotificationContent()
        content.title = "💸 Penalty Applied"
        content.body = "\(amount) will be withdrawn. Snooze #\(snoozeNumber)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Dismiss Handling
    
    @objc private func handleDismiss(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let alarmId = userInfo["alarmId"] as? String else {
            return
        }
        
        // Reset snooze counter
        snoozeCounters.removeValue(forKey: alarmId)
        
        // Cancel any pending snooze notifications
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let snoozeIdentifiers = requests
                .filter { $0.identifier.starts(with: "\(alarmId)-snooze-") }
                .map { $0.identifier }
            
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: snoozeIdentifiers)
        }
        
        print("Alarm dismissed: \(alarmId)")
    }
    
    // MARK: - Get Pending Alarms
    
    func getPendingAlarms() async -> [String] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.map { $0.identifier }
    }
    
    // MARK: - Audio Playback (for foreground alarms)
    
    func playAlarmSound() {
        guard let soundURL = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.play()
        } catch {
            print("Failed to play alarm sound: \(error.localizedDescription)")
        }
    }
    
    func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
