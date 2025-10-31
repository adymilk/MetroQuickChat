import Foundation

/// 存储分析数据模型
public struct StorageAnalysis: Codable {
    /// 应用占用存储大小（字节）
    public let totalSize: Int64
    
    /// 设备总存储空间（字节）
    public let deviceTotalSpace: Int64
    
    /// 设备已用存储空间（字节）
    public let deviceUsedSpace: Int64
    
    /// 文字消息存储大小
    public let textSize: Int64
    
    /// 图片存储大小
    public let imageSize: Int64
    
    /// 视频存储大小
    public let videoSize: Int64
    
    /// 语音存储大小
    public let voiceSize: Int64
    
    /// 其他/元数据存储大小
    public let otherSize: Int64
    
    /// 频道数量
    public let channelCount: Int
    
    /// 消息总数
    public let messageCount: Int
    
    /// 各类型消息数量
    public let textMessageCount: Int
    public let imageMessageCount: Int
    public let videoMessageCount: Int
    public let voiceMessageCount: Int
    
    public init(
        totalSize: Int64 = 0,
        deviceTotalSpace: Int64 = 0,
        deviceUsedSpace: Int64 = 0,
        textSize: Int64 = 0,
        imageSize: Int64 = 0,
        videoSize: Int64 = 0,
        voiceSize: Int64 = 0,
        otherSize: Int64 = 0,
        channelCount: Int = 0,
        messageCount: Int = 0,
        textMessageCount: Int = 0,
        imageMessageCount: Int = 0,
        videoMessageCount: Int = 0,
        voiceMessageCount: Int = 0
    ) {
        self.totalSize = totalSize
        self.deviceTotalSpace = deviceTotalSpace
        self.deviceUsedSpace = deviceUsedSpace
        self.textSize = textSize
        self.imageSize = imageSize
        self.videoSize = videoSize
        self.voiceSize = voiceSize
        self.otherSize = otherSize
        self.channelCount = channelCount
        self.messageCount = messageCount
        self.textMessageCount = textMessageCount
        self.imageMessageCount = imageMessageCount
        self.videoMessageCount = videoMessageCount
        self.voiceMessageCount = voiceMessageCount
    }
    
    // MARK: - 计算属性
    
    /// 文字消息占比（0.0 - 1.0）
    public var textPercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(textSize) / Double(totalSize)
    }
    
    /// 图片占比
    public var imagePercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(imageSize) / Double(totalSize)
    }
    
    /// 视频占比
    public var videoPercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(videoSize) / Double(totalSize)
    }
    
    /// 语音占比
    public var voicePercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(voiceSize) / Double(totalSize)
    }
    
    /// 其他占比
    public var otherPercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(otherSize) / Double(totalSize)
    }
    
    /// 格式化存储大小
    public func formatSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    public var formattedTotalSize: String {
        formatSize(totalSize)
    }
    
    /// 应用占用设备存储的百分比（0.0 - 1.0）
    public var storagePercentage: Double {
        guard deviceTotalSpace > 0 else { return 0.0 }
        return Double(totalSize) / Double(deviceTotalSpace)
    }
}

