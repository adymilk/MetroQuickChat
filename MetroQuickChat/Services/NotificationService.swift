import Foundation
import UserNotifications
import UIKit

/// App 通知服务
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var isAuthorized: Bool = false
    
    private init() {
        checkAuthorization()
    }
    
    /// 检查并请求通知权限
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
            print("NotificationService: 通知权限 \(granted ? "已授予" : "已拒绝")")
        } catch {
            print("NotificationService: 请求通知权限失败: \(error)")
            await MainActor.run {
                self.isAuthorized = false
            }
        }
    }
    
    /// 检查当前授权状态
    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    /// 发送频道发现通知
    func notifyChannelDiscovered(_ channel: Channel) {
        guard isAuthorized else {
            // 如果未授权，尝试请求权限
            Task {
                await requestAuthorization()
                if isAuthorized {
                    sendNotification(for: channel)
                }
            }
            return
        }
        
        sendNotification(for: channel)
    }
    
    /// 发送通知
    private func sendNotification(for channel: Channel) {
        let content = UNMutableNotificationContent()
        content.title = "发现新频道"
        content.body = "附近出现频道：\(channel.name)"
        content.sound = .default
        content.badge = 1
        
        // 添加自定义数据
        content.userInfo = [
            "channelId": channel.id.uuidString,
            "channelName": channel.name
        ]
        
        // 立即触发
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "channel_\(channel.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationService: 发送通知失败: \(error)")
            } else {
                print("NotificationService: 已发送通知 - \(channel.name)")
            }
        }
    }
    
    /// 清除通知徽章
    func clearBadge() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}

