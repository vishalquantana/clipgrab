import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
    }

    func notifyDownloadStarted(platform: String) {
        let content = UNMutableNotificationContent()
        content.title = "ClipGrab"
        content.body = "Downloading from \(platform)..."
        content.sound = nil
        let request = UNNotificationRequest(identifier: "download-started-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyDownloadComplete(title: String, mediaType: String) {
        let content = UNMutableNotificationContent()
        content.title = "ClipGrab"
        content.body = "\(mediaType == "video" ? "Video" : "Photo") ready to paste: \(title)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "download-complete-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyError(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ClipGrab"
        content.body = message
        content.sound = nil
        let request = UNNotificationRequest(identifier: "download-error-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
