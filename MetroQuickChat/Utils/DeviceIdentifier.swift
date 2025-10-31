import Foundation
import UIKit

/// 设备唯一识别码工具
enum DeviceIdentifier {
    /// 获取设备唯一标识符（基于 identifierForVendor，每个应用的供应商唯一）
    /// 注意：identifierForVendor 在同一应用的不同设备间不同，但在同一设备的同一应用内保持一致
    static func deviceId() -> UUID {
        // 使用 identifierForVendor 作为设备唯一标识
        // 如果为 nil（极少情况），生成一个并保存到 UserDefaults
        if let identifier = UIDevice.current.identifierForVendor {
            // 将 identifierForVendor 转换为 UUID 字符串格式，确保一致性
            let uuidString = identifier.uuidString
            return UUID(uuidString: uuidString) ?? generateAndSaveDeviceId()
        } else {
            return generateAndSaveDeviceId()
        }
    }
    
    /// 生成并保存设备ID（回退方案）
    private static func generateAndSaveDeviceId() -> UUID {
        let key = "com.metroquickchat.deviceId"
        if let saved = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: saved) {
            return uuid
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: key)
        return newId
    }
    
    /// 生成带设备ID的完整用户标识（昵称 + 设备ID短码）
    /// 格式：昵称#设备ID前8位
    static func fullUserIdentifier(nickname: String) -> String {
        let deviceId = DeviceIdentifier.deviceId()
        let shortId = deviceId.uuidString.prefix(8)
        return "\(nickname)#\(shortId)"
    }
}

