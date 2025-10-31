import SwiftUI

/// Telegram 风格的单行频道列表项
struct ChannelRowView: View {
    let channel: Channel
    let lastMessage: String?
    let lastMessageTime: Date?
    let unreadCount: Int
    let isFavorite: Bool
    let channelManager: ChannelManager
    
    let onTap: () -> Void
    let onFavoriteToggle: (() -> Void)?
    
    init(
        channel: Channel,
        channelManager: ChannelManager,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onFavoriteToggle: (() -> Void)? = nil
    ) {
        self.channel = channel
        self.channelManager = channelManager
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onFavoriteToggle = onFavoriteToggle
        
        // 获取最后一条消息
        let messages = channelManager.store.loadMessages(channelId: channel.id)
        let userMessages = messages.filter { $0.author != .system }
        if let lastMsg = userMessages.last {
            self.lastMessage = lastMsg.displayText
            self.lastMessageTime = lastMsg.createdAt
            // 计算未读数（简单实现：暂时为0，后续可以优化）
            self.unreadCount = 0
        } else {
            self.lastMessage = nil
            self.lastMessageTime = channel.createdAt
            self.unreadCount = 0
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 左侧头像
                ChannelAvatarView(name: channel.name, size: 50)
                
                // 中间内容
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        // 收藏标记
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                        }
                        
                        // 在线状态指示器
                        if channel.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    // 最后消息预览
                    if let lastMessage = lastMessage {
                        Text(lastMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("暂无消息")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
                
                Spacer()
                
                // 右侧信息
                VStack(alignment: .trailing, spacing: 4) {
                    // 时间戳
                    if let time = lastMessageTime {
                        Text(formatTime(time))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // 未读数标记（如果有）
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                            .frame(minWidth: 20)
                    }
                    
                    // 已读标记（暂无未读数时显示）
                    if unreadCount == 0, lastMessage != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onFavoriteToggle = onFavoriteToggle {
                Button(action: onFavoriteToggle) {
                    Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.slash.fill" : "star.fill")
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let timeString = formatter.string(from: date)
            // 转换为小写并移除 AM/PM（简化显示）
            return timeString.replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "")
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) ?? false {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Channel Avatar View

private struct ChannelAvatarView: View {
    let name: String
    let size: CGFloat
    
    // 从名称生成颜色
    private var backgroundColor: Color {
        let hash = name.hashValue
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .red, .cyan, .indigo
        ]
        return colors[abs(hash) % colors.count]
    }
    
    // 从名称提取首字符
    private var initials: String {
        let components = name.components(separatedBy: .whitespacesAndNewlines)
        if let first = components.first?.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
                .frame(width: size, height: size)
            
            Circle()
                .fill(backgroundColor)
                .frame(width: size - 2, height: size - 2)
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct ChannelRowView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ChannelRowView(
                channel: Channel(name: "晚高峰 2号线 A车厢", hostPeerId: UUID()),
                channelManager: ChannelManager(
                    central: BluetoothCentralManager(),
                    peripheral: BluetoothPeripheralManager(),
                    selfPeer: Peer(nickname: "测试")
                ),
                isFavorite: true,
                onTap: {},
                onFavoriteToggle: {}
            )
            
            ChannelRowView(
                channel: Channel(name: "Digital Nomads", hostPeerId: UUID()),
                channelManager: ChannelManager(
                    central: BluetoothCentralManager(),
                    peripheral: BluetoothPeripheralManager(),
                    selfPeer: Peer(nickname: "测试")
                ),
                onTap: {},
                onFavoriteToggle: {}
            )
        }
        .listStyle(.plain)
    }
}

