import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure push notifications
        configureNotifications(application)
        
        return true
    }
    
    // MARK: - Push Notifications
    
    private func configureNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
            print("Notification permission granted: \(granted)")
        }
        
        application.registerForRemoteNotifications()
        
        // Configure Firebase Messaging
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

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle different notification actions
        switch response.actionIdentifier {
        case "SNOOZE_ACTION":
            handleSnoozeAction(userInfo: userInfo)
        case "DISMISS_ACTION":
            handleDismissAction(userInfo: userInfo)
        default:
            break
        }
        
        completionHandler()
    }
    
    private func handleSnoozeAction(userInfo: [AnyHashable: Any]) {
        // Post notification for AlarmService to handle
        NotificationCenter.default.post(
            name: .alarmSnoozed,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleDismissAction(userInfo: [AnyHashable: Any]) {
        // Post notification for AlarmService to handle
        NotificationCenter.default.post(
            name: .alarmDismissed,
            object: nil,
            userInfo: userInfo
        )
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM Token: \(token)")
        
        // Send token to backend for push notifications (MMF feature)
        // APIService.shared.updateFCMToken(token)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let alarmSnoozed = Notification.Name("alarmSnoozed")
    static let alarmDismissed = Notification.Name("alarmDismissed")
    static let alarmTriggered = Notification.Name("alarmTriggered")
}
