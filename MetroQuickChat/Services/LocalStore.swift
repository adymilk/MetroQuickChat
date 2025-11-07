import Foundation
import Combine
import UIKit

/// 永久存储聊天数据到本地文件系统
/// 使用 Application Support 目录，确保数据在应用更新后仍然保留
final class LocalStore {
    enum StoreError: Error { 
        case ioFailed 
        case encodingFailed
        case decodingFailed
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [] // 不格式化，节省空间
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let baseURL: URL
    private let fileManager = FileManager.default
    
    // 批量写入队列：避免频繁写入文件
    private var pendingMessages: [UUID: [Message]] = [:] // channelId -> pending messages
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0 // 2秒后批量保存
    
    // 内存缓存：避免重复读取
    private var messageCache: [UUID: [Message]] = [:]

    init() {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var app = dir.appendingPathComponent("MetroQuickChat", isDirectory: true)
        
        // 确保目录存在，并设置为永久存储
        do {
            if !fileManager.fileExists(atPath: app.path) {
                try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
            }
            // 设置目录属性，确保不会被系统清理
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false // 允许备份，确保永久保存
            try app.setResourceValues(resourceValues)
        } catch {
            print("LocalStore: 创建存储目录失败: \(error)")
        }
        
        baseURL = app
        
        // 监听应用进入后台，立即保存所有待写入的消息
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPendingMessages()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPendingMessages()
        }
    }
    
    deinit {
        saveTimer?.invalidate()
        // 在 deinit 时同步保存所有待写入的消息
        if !pendingMessages.isEmpty {
            let channelsToSave = pendingMessages
            for (channelId, messages) in channelsToSave {
                saveMessages(channelId: channelId, messages: messages)
            }
        }
        NotificationCenter.default.removeObserver(self)
    }

    /// 加载频道的所有消息（永久存储）
    func loadMessages(channelId: UUID) -> [Message] {
        // 先检查缓存
        if let cached = messageCache[channelId] {
            return cached
        }
        
        let url = baseURL.appendingPathComponent("messages_\(channelId.uuidString).json")
        
        guard fileManager.fileExists(atPath: url.path) else {
            messageCache[channelId] = []
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let messages = try decoder.decode([Message].self, from: data)
            messageCache[channelId] = messages
            print("LocalStore: 成功加载 \(messages.count) 条消息 (频道: \(channelId.uuidString.prefix(8)))")
            return messages
        } catch {
            print("LocalStore: 加载消息失败: \(error)")
            // 尝试备份文件
            let backupURL = url.appendingPathExtension("backup")
            try? fileManager.copyItem(at: url, to: backupURL)
            return []
        }
    }

    /// 添加消息到永久存储（批量写入优化）
    func appendMessage(_ message: Message) {
        let channelId = message.channelId
        
        // 更新内存缓存
        if messageCache[channelId] == nil {
            messageCache[channelId] = loadMessages(channelId: channelId)
        }
        messageCache[channelId]?.append(message)
        
        // 添加到待写入队列
        if pendingMessages[channelId] == nil {
            pendingMessages[channelId] = []
        }
        pendingMessages[channelId]?.append(message)
        
        // 启动或重置保存定时器
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.flushPendingMessages()
        }
    }
    
    /// 立即保存所有待写入的消息
    private func flushPendingMessages() {
        saveTimer?.invalidate()
        saveTimer = nil
        
        guard !pendingMessages.isEmpty else { return }
        
        let channelsToSave = pendingMessages
        pendingMessages.removeAll()
        
        for (channelId, messages) in channelsToSave {
            saveMessages(channelId: channelId, messages: messages)
        }
        
        print("LocalStore: 批量保存完成，共 \(channelsToSave.count) 个频道")
    }
    
    /// 保存消息到文件（带错误处理和重试）
    private func saveMessages(channelId: UUID, messages: [Message]) {
        let url = baseURL.appendingPathComponent("messages_\(channelId.uuidString).json")
        
        // 加载现有消息
        var allMessages: [Message]
        if let cached = messageCache[channelId] {
            allMessages = cached
        } else {
            allMessages = loadMessages(channelId: channelId)
        }
        
        // 去重：避免重复消息
        let existingIds = Set(allMessages.map { $0.id })
        let newMessages = messages.filter { !existingIds.contains($0.id) }
        allMessages.append(contentsOf: newMessages)
        
        // 保存到文件
        do {
            let data = try encoder.encode(allMessages)
            
            // 使用原子写入，确保数据完整性
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            
            // 更新缓存
            messageCache[channelId] = allMessages
            
            print("LocalStore: 成功保存 \(newMessages.count) 条新消息 (频道: \(channelId.uuidString.prefix(8)), 总计: \(allMessages.count))")
        } catch {
            print("LocalStore: 保存消息失败: \(error)")
            // 保存失败时，将消息重新加入待写入队列
            if pendingMessages[channelId] == nil {
                pendingMessages[channelId] = []
            }
            pendingMessages[channelId]?.append(contentsOf: newMessages)
        }
    }

    /// 清空频道的所有消息
    func clearMessages(channelId: UUID) {
        let url = baseURL.appendingPathComponent("messages_\(channelId.uuidString).json")
        
        // 清除缓存
        messageCache.removeValue(forKey: channelId)
        pendingMessages.removeValue(forKey: channelId)
        
        // 删除文件
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("LocalStore: 已清空频道消息: \(channelId.uuidString.prefix(8))")
            }
        } catch {
            print("LocalStore: 清空消息失败: \(error)")
        }
    }
    
    /// 删除单条消息
    func deleteMessage(messageId: UUID, channelId: UUID) {
        let url = baseURL.appendingPathComponent("messages_\(channelId.uuidString).json")
        
        // 从缓存中删除
        messageCache[channelId]?.removeAll { $0.id == messageId }
        
        // 从文件中删除
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var messages = try? decoder.decode([Message].self, from: data) else {
            return
        }
        
        messages.removeAll { $0.id == messageId }
        
        do {
            let encoded = try encoder.encode(messages)
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
            messageCache[channelId] = messages
            print("LocalStore: 已删除消息: \(messageId.uuidString.prefix(8))")
        } catch {
            print("LocalStore: 删除消息失败: \(error)")
        }
    }
    
    /// 获取所有已存储的频道ID
    func getAllChannelIds() -> [UUID] {
        guard let files = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        // 只返回有消息的频道ID（过滤掉空文件或无效的频道）
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("messages_") }
            .compactMap { url -> UUID? in
                let fileName = url.deletingPathExtension().lastPathComponent
                let uuidString = fileName.replacingOccurrences(of: "messages_", with: "")
                guard let channelId = UUID(uuidString: uuidString) else { return nil }
                
                // 验证文件确实有消息内容（避免统计空文件）
                let messages = loadMessages(channelId: channelId)
                return messages.isEmpty ? nil : channelId
            }
    }
    
    /// 获取存储统计信息
    func getStorageInfo() -> (totalChannels: Int, totalMessages: Int) {
        let channelIds = getAllChannelIds()
        let totalMessages = channelIds.reduce(0) { count, channelId in
            count + loadMessages(channelId: channelId).count
        }
        return (channelIds.count, totalMessages)
    }
    
    // MARK: - Favorite Channels
    
    /// 保存收藏的频道
    func saveFavoriteChannel(_ channel: Channel) {
        var favorites = loadFavoriteChannels()
        // 检查是否已存在
        if favorites.contains(where: { $0.id == channel.id }) {
            // 更新现有收藏
            if let index = favorites.firstIndex(where: { $0.id == channel.id }) {
                favorites[index] = channel
            }
        } else {
            // 添加新收藏
            favorites.append(channel)
        }
        
        let url = baseURL.appendingPathComponent("favorite_channels.json")
        do {
            let data = try encoder.encode(favorites)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("LocalStore: 已保存收藏频道: \(channel.name)")
        } catch {
            print("LocalStore: 保存收藏频道失败: \(error)")
        }
    }
    
    /// 加载所有收藏的频道
    func loadFavoriteChannels() -> [Channel] {
        let url = baseURL.appendingPathComponent("favorite_channels.json")
        
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let channels = try decoder.decode([Channel].self, from: data)
            print("LocalStore: 加载了 \(channels.count) 个收藏频道")
            return channels
        } catch {
            print("LocalStore: 加载收藏频道失败: \(error)")
            return []
        }
    }
    
    /// 删除收藏的频道
    func removeFavoriteChannel(channelId: UUID) {
        var favorites = loadFavoriteChannels()
        favorites.removeAll { $0.id == channelId }
        
        let url = baseURL.appendingPathComponent("favorite_channels.json")
        do {
            let data = try encoder.encode(favorites)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("LocalStore: 已删除收藏频道: \(channelId.uuidString.prefix(8))")
        } catch {
            print("LocalStore: 删除收藏频道失败: \(error)")
        }
    }
    
    /// 检查频道是否已收藏
    func isFavoriteChannel(channelId: UUID) -> Bool {
        let favorites = loadFavoriteChannels()
        return favorites.contains(where: { $0.id == channelId })
    }
    
    // MARK: - Storage Analysis
    
    /// 分析存储使用情况（使用真实文件系统数据）
    func analyzeStorage() -> StorageAnalysis {
        var textSize: Int64 = 0
        var imageSize: Int64 = 0
        var videoSize: Int64 = 0
        var voiceSize: Int64 = 0
        var channelCount = 0
        var messageCount = 0
        var textMessageCount = 0
        var imageMessageCount = 0
        var videoMessageCount = 0
        var voiceMessageCount = 0
        
        // 使用递归方式获取所有文件的实际大小（包括子目录）
        let totalSize = getStorageDirectorySize()
        
        // 分析所有频道的消息
        let channelIds = getAllChannelIds()
        channelCount = channelIds.count
        
        for channelId in channelIds {
            let messages = loadMessages(channelId: channelId)
            messageCount += messages.count
            
            for message in messages {
                let isSystemMessage = message.author == .system
                
                // 计算消息大小（所有消息都计入总大小，因为 totalSize 是从文件系统读取的真实值）
                // 这里计算的是消息 JSON 编码后的元数据大小，用于分类统计
                if let encoded = try? encoder.encode(message) {
                    let messageSize = Int64(encoded.count)
                    
                    // 系统消息不计入具体类型，但会通过 otherSize 计算时包含
                    if isSystemMessage {
                        // 系统消息继续循环，不进行分类统计
                        continue
                    }
                    
                    // 根据消息类型分类（只统计用户消息）
                    if let messageType = message.messageType {
                        switch messageType {
                        case .text, .emoji:
                            textSize += messageSize
                            textMessageCount += 1
                        case .image(let data):
                            imageSize += messageSize
                            imageSize += Int64(data.count) // 图片数据大小（真实数据）
                            imageMessageCount += 1
                        case .voice(let data, _):
                            voiceSize += messageSize
                            voiceSize += Int64(data.count) // 语音数据大小（真实数据）
                            voiceMessageCount += 1
                        case .video(let data, _, _):
                            // 视频也计入媒体大小，但可能需要单独统计
                            imageSize += messageSize // 暂时归入 imageSize，因为都是媒体文件
                            imageSize += Int64(data.count) // 视频数据大小（真实数据）
                            imageMessageCount += 1 // 暂时计入图片数量
                        }
                    } else if message.attachment != nil {
                        // 旧版附件格式
                        if let attachment = message.attachment {
                            if attachment.kind == .image {
                                imageSize += messageSize
                                // 计算 base64 解码后的实际数据大小
                                if let data = Data(base64Encoded: attachment.dataBase64) {
                                    imageSize += Int64(data.count)
                                }
                                // 如果还有缩略图，也计算大小
                                if let thumbnailBase64 = attachment.thumbnailBase64,
                                   let thumbData = Data(base64Encoded: thumbnailBase64) {
                                    imageSize += Int64(thumbData.count)
                                }
                                imageMessageCount += 1
                            } else if attachment.kind == .video {
                                videoSize += messageSize
                                // 计算 base64 解码后的实际数据大小
                                if let data = Data(base64Encoded: attachment.dataBase64) {
                                    videoSize += Int64(data.count)
                                }
                                // 如果还有缩略图，也计算大小
                                if let thumbnailBase64 = attachment.thumbnailBase64,
                                   let thumbData = Data(base64Encoded: thumbnailBase64) {
                                    videoSize += Int64(thumbData.count)
                                }
                                videoMessageCount += 1
                            }
                        }
                    } else {
                        // 纯文字消息（无 messageType，也无 attachment）
                        textSize += messageSize
                        textMessageCount += 1
                    }
                }
            }
        }
        
        // 计算其他大小（元数据、索引文件等）
        let otherSize = totalSize - textSize - imageSize - videoSize - voiceSize
        
        // 获取设备存储信息
        let deviceTotalSpace = DeviceStorageInfo.totalDiskSpace()
        let deviceUsedSpace = DeviceStorageInfo.usedDiskSpace()
        
        return StorageAnalysis(
            totalSize: totalSize,
            deviceTotalSpace: deviceTotalSpace,
            deviceUsedSpace: deviceUsedSpace,
            textSize: textSize,
            imageSize: imageSize,
            videoSize: videoSize,
            voiceSize: voiceSize,
            otherSize: max(0, otherSize), // 确保不为负
            channelCount: channelCount,
            messageCount: messageCount,
            textMessageCount: textMessageCount,
            imageMessageCount: imageMessageCount,
            videoMessageCount: videoMessageCount,
            voiceMessageCount: voiceMessageCount
        )
    }
    
    /// 获取存储目录大小（直接计算文件系统）
    func getStorageDirectorySize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               let isDirectory = resourceValues.isDirectory,
               !isDirectory,
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// 清理指定频道的消息（保留频道记录）
    func clearChannelMessages(channelId: UUID) {
        let url = baseURL.appendingPathComponent("messages_\(channelId.uuidString).json")
        try? fileManager.removeItem(at: url)
        messageCache.removeValue(forKey: channelId)
    }
    
    /// 清理所有消息但保留频道列表
    func clearAllMessages() {
        let channelIds = getAllChannelIds()
        for channelId in channelIds {
            clearChannelMessages(channelId: channelId)
        }
    }
    
    /// 清理所有数据（包括收藏列表）
    func clearAllData() {
        // 删除所有文件
        if let files = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        messageCache.removeAll()
    }
    
    /// 获取所有加入过的频道（从消息文件中提取）
    func getAllJoinedChannels() -> [UUID] {
        return getAllChannelIds()
    }
    
    /// 获取指定类型的所有消息文件列表
    func getAllMessageFiles(byType fileType: MessageFileItem.FileType, channelNameProvider: (UUID) -> String? = { _ in nil }) -> [MessageFileItem] {
        var items: [MessageFileItem] = []
        let channelIds = getAllChannelIds()
        
        for channelId in channelIds {
            let messages = loadMessages(channelId: channelId)
            let channelName = channelNameProvider(channelId)
            
            for message in messages {
                let item = MessageFileItem(message: message, channelName: channelName)
                
                // 根据类型筛选
                switch fileType {
                case .text:
                    if item.fileType == .text {
                        items.append(item)
                    }
                case .image:
                    if item.fileType == .image {
                        items.append(item)
                    }
                case .video:
                    if item.fileType == .video {
                        items.append(item)
                    }
                case .voice:
                    if item.fileType == .voice {
                        items.append(item)
                    }
                case .other:
                    if item.fileType == .other {
                        items.append(item)
                    }
                }
            }
        }
        
        // 按创建时间倒序排序
        return items.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// 根据 MessageFileItem 的 messageId 和 channelId 加载完整消息
    func loadMessage(for item: MessageFileItem) -> Message? {
        let messages = loadMessages(channelId: item.channelId)
        return messages.first { $0.id == item.messageId }
    }
    
    // MARK: - Data Cleanup
    
    /// 清理错误和无效的数据文件
    /// 返回：(清理的文件数量, 释放的存储空间)
    func cleanupInvalidData() -> (removedFiles: Int, freedSpace: Int64) {
        var removedCount = 0
        var freedSpace: Int64 = 0
        
        // 获取所有文件
        guard let files = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return (0, 0)
        }
        
        // 获取所有有效的频道 ID（从收藏列表和有消息的频道）
        let favoriteChannelIds = Set(loadFavoriteChannels().map { $0.id })
        let validChannelIds = Set(getAllChannelIds())
        let allValidChannelIds = favoriteChannelIds.union(validChannelIds)
        
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            
            // 跳过目录
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            
            // 检查是否是消息文件
            if fileName.hasPrefix("messages_") && fileName.hasSuffix(".json") {
                let uuidString = String(fileName.dropFirst("messages_".count).dropLast(".json".count))
                guard let channelId = UUID(uuidString: uuidString) else {
                    // 无效的 UUID，删除
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        freedSpace += Int64(size)
                    }
                    try? fileManager.removeItem(at: fileURL)
                    removedCount += 1
                    print("LocalStore: 删除无效的消息文件（UUID格式错误）: \(fileName)")
                    continue
                }
                
                // 尝试加载并验证消息文件
                do {
                    let data = try Data(contentsOf: fileURL)
                    let messages = try decoder.decode([Message].self, from: data)
                    
                    // 如果文件为空或无效，且频道不在有效列表中，删除
                    if messages.isEmpty && !allValidChannelIds.contains(channelId) {
                        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            freedSpace += Int64(size)
                        }
                        try? fileManager.removeItem(at: fileURL)
                        messageCache.removeValue(forKey: channelId)
                        removedCount += 1
                        print("LocalStore: 删除空消息文件: \(fileName)")
                    }
                } catch {
                    // 文件损坏或无法解析，删除
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        freedSpace += Int64(size)
                    }
                    try? fileManager.removeItem(at: fileURL)
                    messageCache.removeValue(forKey: channelId)
                    removedCount += 1
                    print("LocalStore: 删除损坏的消息文件: \(fileName) - 错误: \(error.localizedDescription)")
                }
            } else if fileName != "favorite_channels.json" {
                // 未知文件类型（除了收藏列表文件），检查是否需要清理
                // 这里可以扩展更多清理逻辑
            }
        }
        
        // 清理缓存中的无效条目
        messageCache = messageCache.filter { channelId, _ in
            allValidChannelIds.contains(channelId) || fileManager.fileExists(atPath: baseURL.appendingPathComponent("messages_\(channelId.uuidString).json").path)
        }
        
        print("LocalStore: 清理完成 - 删除 \(removedCount) 个文件，释放 \(DeviceStorageInfo.formattedSize(freedSpace))")
        return (removedCount, freedSpace)
    }
}



