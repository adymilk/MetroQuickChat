import SwiftUI

struct ChannelInfoEditView: View {
    let channel: Channel
    @ObservedObject var channelManager: ChannelManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var channelName: String
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    init(channel: Channel, channelManager: ChannelManager) {
        self.channel = channel
        self.channelManager = channelManager
        _channelName = State(initialValue: channel.name)
    }
    
    private var isHost: Bool {
        channelManager.isCurrentUserHost()
    }
    
    private var hostPeer: Peer? {
        channelManager.getHostPeer()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 频道名称（只有房主可以编辑）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("频道名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if isHost {
                            TextField("输入频道名称", text: $channelName)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(channelName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("基本信息")
                } footer: {
                    if !isHost {
                        Text("只有房主可以修改频道信息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 房主信息
                Section {
                    HStack(spacing: 12) {
                        // 房主头像
                        AvatarView(nickname: hostPeer?.nickname ?? "未知", size: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(hostPeer?.nickname ?? "未知房主")
                                    .font(.headline)
                                
                                // 房主标识
                                Text("房主")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                            }
                            
                            if let hostPeer = hostPeer {
                                HStack(spacing: 8) {
                                    // 距离
                                    if let distanceText = distanceText(for: hostPeer) {
                                        Label(distanceText, systemImage: "location")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    // 在线时长
                                    if let onlineDuration = onlineDurationText(for: hostPeer) {
                                        Label(onlineDuration, systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("房主信息")
                } footer: {
                    Text("房主拥有管理频道的权限，可以修改频道名称、踢出成员、解散频道等")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 频道统计
                Section {
                    HStack {
                        Text("创建时间")
                        Spacer()
                        Text(formatDate(channel.createdAt))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("频道ID")
                        Spacer()
                        Text(channel.id.uuidString.prefix(8))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("频道详情")
                }
            }
            .navigationTitle("频道信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                if isHost {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            saveChannelInfo()
                        }
                        .disabled(channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("好", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveChannelInfo() {
        let trimmedName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "频道名称不能为空"
            showError = true
            return
        }
        
        guard trimmedName != channel.name else {
            // 名称未改变，直接关闭
            dismiss()
            return
        }
        
        // 更新频道名称
        channelManager.updateChannelName(trimmedName)
        Haptics.success()
        dismiss()
    }
    
    private func distanceText(for peer: Peer) -> String? {
        guard let plat = peer.latitude, let plon = peer.longitude,
              let locationProvider = channelManager.locationProvider.location else { return nil }
        let peerLocation = CLLocation(latitude: plat, longitude: plon)
        let meters = peerLocation.distance(from: locationProvider)
        if meters < 1000 {
            return String(format: "%.0f 米", meters)
        }
        return String(format: "%.2f 公里", meters / 1000)
    }
    
    private func onlineDurationText(for peer: Peer) -> String? {
        guard let lastUpdated = peer.lastUpdatedAt else { return nil }
        let duration = Date().timeIntervalSince(lastUpdated)
        
        if duration < 60 {
            return "刚刚在线"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "在线 \(minutes) 分钟"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "在线 \(hours) 小时"
        } else {
            let days = Int(duration / 86400)
            return "在线 \(days) 天"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

import CoreLocation

// MARK: - Avatar View
private struct AvatarView: View {
    let nickname: String
    let size: CGFloat
    
    private var avatarColor: Color {
        let hash = abs(nickname.hashValue)
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .red, .cyan, .indigo
        ]
        return colors[hash % colors.count]
    }
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [avatarColor.opacity(0.6), avatarColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(String(nickname.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Preview
struct ChannelInfoEditView_Previews: PreviewProvider {
    static var previews: some View {
        let channel = Channel(name: "测试频道", hostPeerId: UUID())
        let peer = Peer(nickname: "房主", isHost: true)
        let manager = ChannelManager(
            central: BluetoothCentralManager(),
            peripheral: BluetoothPeripheralManager(),
            selfPeer: peer
        )
        ChannelInfoEditView(channel: channel, channelManager: manager)
    }
}
