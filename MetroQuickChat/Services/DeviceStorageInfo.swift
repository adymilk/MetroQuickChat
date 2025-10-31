import Foundation
import UIKit

/// 设备存储信息工具类
struct DeviceStorageInfo {
    /// 获取设备总存储空间（字节）
    static func totalDiskSpace() -> Int64 {
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let totalSpace = systemAttributes[.systemSize] as? NSNumber else {
            return 0
        }
        return totalSpace.int64Value
    }
    
    /// 获取设备可用存储空间（字节）
    static func availableDiskSpace() -> Int64 {
        guard let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = systemAttributes[.systemFreeSize] as? NSNumber else {
            return 0
        }
        return freeSpace.int64Value
    }
    
    /// 获取设备已用存储空间（字节）
    static func usedDiskSpace() -> Int64 {
        let total = totalDiskSpace()
        let available = availableDiskSpace()
        return total - available
    }
    
    /// 计算应用占用设备存储的百分比（0.0 - 1.0）
    static func calculateStoragePercentage(appSize: Int64) -> Double {
        let total = totalDiskSpace()
        guard total > 0 else { return 0.0 }
        return Double(appSize) / Double(total)
    }
    
    /// 格式化存储大小
    static func formattedSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

