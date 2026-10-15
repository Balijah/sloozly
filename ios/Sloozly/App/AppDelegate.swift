import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        
        // Register for remote (push) notifications only.
        // Local alarm alerts are now handled by AlarmKit.
        configurePushNotifications(application)
        
        // Prune old snooze events
        SnoozeEventStore.shared.pruneOldEvents()
        
        // Process any pending snooze events from previous sessions
        Task {
            await SnoozeEventQueue.shared.processQueue()
        }
        
        return true
    }
    
    // MARK: - Push Notifications (for server-sent alerts, not alarms)
    
    private func configurePushNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                print("Push notification authorization error: \(error.localizedDescription)")
            }
            print("Push notification permission granted: \(granted)")
        }
        
        application.registerForRemoteNotifications()
        
        Messaging.messaging().delegate = self
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

// MARK: - UNUserNotificationCenterDelegate (push notifications only)

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM Token: \(token)")
        
        Task {
            do {
                try await APIService.shared.updateFCMToken(token)
            } catch {
                print("Failed to send FCM token to backend: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let alarmSnoozed = Notification.Name("alarmSnoozed")
    static let alarmDismissed = Notification.Name("alarmDismissed")
    static let alarmTriggered = Notification.Name("alarmTriggered")
}
