/*
 * ChatView - Telegram-like UI
 *
 * To use Exyte.Chat library:
 * 1. Add package: https://github.com/exyte/Chat (version 2.0.0+)
 * 2. Import: import ExyteChat
 * 3. This implementation works standalone but can be enhanced with Exyte.Chat
 */

import SwiftUI
import PhotosUI

@MainActor
struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ChatViewModel
    @State private var showMembers: Bool = false
    @State private var showToast: Bool = false
    @State private var toastText: String = "已发送"
    @State private var pendingReport: Message? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var videoPickerItem: PhotosPickerItem? = nil
    @State private var isLongPressingVoice: Bool = false
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @State private var showEmojiPicker: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var isChannelFavorite: Bool = false
    @State private var showChannelInfo: Bool = false
    
    init(channel: Channel, channelManager: ChannelManager?) {
        let manager = channelManager ?? ChannelManager(central: BluetoothCentralManager(), peripheral: BluetoothPeripheralManager(), selfPeer: Peer(nickname: UserDefaults.standard.string(forKey: "nickname") ?? "用户"))
        _viewModel = StateObject(wrappedValue: ChatViewModel(channelManager: manager, channel: channel))
    }

    private var errorBinding: Binding<Err?> {
        Binding<Err?>(
            get: { viewModel.errorMessage.map { Err(id: UUID(), message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                peer: findPeer(for: message),
                                viewModel: viewModel,
                                isPlaying: viewModel.playingVoiceId == message.id,
                                playbackProgress: viewModel.voiceService.playbackProgress,
                                onCopy: { copyMessage(message) },
                                onDelete: { deleteMessage(message) },
                                onReport: { pendingReport = message },
                                onPlayVoice: { viewModel.playVoice(message: message) },
                                onImageTap: { img in selectedImage = img }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    if let last = viewModel.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.errorMessage) { error in
                    if let error = error {
                        toastText = error
                        showToast = true
                    }
                }
                .onChange(of: viewModel.voiceService.isPlaying) { _ in
                    if !viewModel.voiceService.isPlaying {
                        viewModel.playingVoiceId = nil
                    }
                }
            }
            
            // Input bar
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text(viewModel.channel.name)
                            .font(.system(size: 17, weight: .semibold))
                        
                        // 房主标识（仅在标题栏显示，如果是自己）
                        if viewModel.isHost {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                    }
                    
                    if !viewModel.peers.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(viewModel.peers.count) 成员")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            
                            // 显示房主昵称
                            if let hostPeer = viewModel.getHostPeer(), !viewModel.isHost {
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text("房主：\(hostPeer.nickname)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // 收藏按钮
                Button {
                    if isChannelFavorite {
                        viewModel.channelManager.unfavoriteChannel(channelId: viewModel.channel.id)
                        isChannelFavorite = false
                        toastText = "已取消收藏"
                        showToast = true
                        Haptics.light()
                    } else {
                        viewModel.channelManager.favoriteChannel(viewModel.channel)
                        isChannelFavorite = true
                        toastText = "已收藏"
                        showToast = true
                        Haptics.success()
                    }
                } label: {
                    Image(systemName: isChannelFavorite ? "star.fill" : "star")
                        .foregroundStyle(isChannelFavorite ? .yellow : .secondary)
                        .symbolEffect(.bounce, value: isChannelFavorite)
                }
                
                // 显示成员头像预览
                if !viewModel.peers.isEmpty {
                    memberAvatarsPreview
                }
                Button { showMembers = true } label: {
                    Image(systemName: "person.3")
                }
                Menu {
                    // 频道信息（所有用户可见）
                    Button {
                        showChannelInfo = true
                        Haptics.light()
                    } label: {
                        Label("频道信息", systemImage: "info.circle")
                    }
                    
                    Divider()
                    
                    Button("离开", action: viewModel.leave)
                    
                    if viewModel.isHost {
                        Divider()
                        Button("解散频道", role: .destructive, action: viewModel.dissolve)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(item: errorBinding) { err in
            Alert(title: Text("错误"), message: Text(err.message), dismissButton: .default(Text("好")))
        }
        .alert(item: $pendingReport) { message in
            Alert(
                title: Text("举报此消息？"),
                message: Text(message.displayText),
                primaryButton: .destructive(Text("举报")) { Haptics.warning() },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showMembers) {
            MembersSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .toast(isPresented: $showToast, text: toastText)
        .onAppear {
            isChannelFavorite = viewModel.channelManager.isFavoriteChannel(channelId: viewModel.channel.id)
            // 重置退出状态，防止误触发
            viewModel.didExitChannel = false
            
            // 确保当前频道状态正确
            let currentChannelId = viewModel.channelManager.currentChannel?.id
            if currentChannelId != viewModel.channel.id {
                // 如果状态不一致，说明可能是新进入的频道，加入它
                // 注意：这里调用 joinChannel 不会触发 .left 事件（因为已经修改了 joinChannel 逻辑）
                Task { @MainActor in
                    // 稍微延迟，确保导航完成
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    viewModel.channelManager.joinChannel(viewModel.channel)
                }
            }
        }
        .onChange(of: viewModel.didExitChannel) { oldValue, newValue in
            // 只有从 false 变为 true 时才真正触发退出（防止初始化时的误触发）
            if !oldValue && newValue {
                // 再次确认：检查当前频道是否真的是 nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                    // 如果 ChannelManager 的 currentChannel 不是当前频道，才真正退出
                    if viewModel.channelManager.currentChannel?.id != viewModel.channel.id {
                        dismiss()
                    } else {
                        // 如果状态恢复了，取消退出
                        viewModel.didExitChannel = false
                    }
                }
            }
        }
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            if let transferable = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: transferable)?.resized(maxWidth: 640).jpegData(compressionQuality: 0.6) {
                    viewModel.sendImage(image)
                    toastText = "图片已发送"
                    showToast = true
                } else {
                    toastText = "图片处理失败"
                    showToast = true
                }
            }
            pickerItem = nil
        }
        .task(id: videoPickerItem) {
            guard let item = videoPickerItem else { return }
            
            // 尝试加载视频数据
            do {
                // 首先尝试作为URL加载（视频文件通常很大，作为URL更高效）
                if let videoURL = try? await item.loadTransferable(type: URL.self),
                   let videoData = try? Data(contentsOf: videoURL) {
                    // 从URL加载数据成功
                    // 尝试生成缩略图
                    var thumbnail: Data? = nil
                    var duration: Int? = nil
                    
                    // 使用 AVFoundation 生成缩略图（如果需要）
                    // 这里简化处理，实际可以使用 AVAssetImageGenerator
                    
                    // 发送视频
                    viewModel.sendVideo(videoData, thumbnail: thumbnail, duration: duration)
                    toastText = "视频已发送"
                    showToast = true
                } else if let videoData = try? await item.loadTransferable(type: Data.self) {
                    // Fallback: 直接加载Data
                    viewModel.sendVideo(videoData, thumbnail: nil, duration: nil)
                    toastText = "视频已发送"
                    showToast = true
                } else {
                    toastText = "视频加载失败，请确保视频文件未损坏"
                    showToast = true
                }
            } catch {
                toastText = "视频处理失败: \(error.localizedDescription)"
                showToast = true
            }
            videoPickerItem = nil
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView { emoji in
                viewModel.inputText.append(emoji)
            }
        }
        .sheet(isPresented: $showChannelInfo) {
            ChannelInfoEditView(channel: viewModel.channel, channelManager: viewModel.channelManager)
        }
        .fullScreenCover(item: Binding(
            get: { selectedImage.map { ImageViewerItem(image: $0) } },
            set: { selectedImage = $0?.image }
        )) { item in
            ImageViewer(image: item.image)
        }
    }
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // 录音时的UI（完全替换输入栏）- 参考设计图
            if viewModel.voiceService.isRecording {
                recordingVoiceUI
            } else {
                // 正常的输入栏
                HStack(spacing: 8) {
                    // Attachment button (left) - Telegram style paperclip
                    Menu {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("照片", systemImage: "photo")
                        }
                        PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                            Label("视频", systemImage: "video")
                        }
                        Button(action: { showEmojiPicker = true }) {
                            Label("表情", systemImage: "face.smiling")
                        }
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 44, height: 44)
                    }
                    
                    // Text input field - Telegram style
                    HStack(spacing: 6) {
                        TextField("Message", text: $viewModel.inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                            .lineLimit(1...5)
                            .focused($isInputFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                // 回车发送消息
                                let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                viewModel.send()
                                toastText = "已发送"
                                showToast = true
                                // 保持焦点，方便连续输入
                            }
                        
                        // Show send button when text exists, otherwise show voice button
                        if !viewModel.inputText.isEmpty {
                            Button(action: {
                                let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                viewModel.send()
                                toastText = "已发送"
                                showToast = true
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        } else {
                            // Voice button with LongPressGesture - Telegram style
                            Button(action: {
                                // 空操作，防止与手势冲突
                            }) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(.secondaryLabel))
                                    .frame(width: 36, height: 36)
                            }
                            .highPriorityGesture(
                                LongPressGesture(minimumDuration: 0.2)
                                    .onEnded { _ in
                                        guard !isLongPressingVoice else { return }
                                        isLongPressingVoice = true
                                        Haptics.light()
                                        viewModel.startVoiceRecord()
                                    }
                                    .sequenced(before: DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard isLongPressingVoice else { return }
                                            let dragDistance = abs(value.translation.height)
                                            dragOffset = value.translation.height
                                            
                                            if dragDistance > 80 {
                                                // 拖动距离超过阈值，显示取消状态
                                                if !viewModel.voiceService.isRecording || isLongPressingVoice {
                                                    // 保持录音状态，但提示可以取消
                                                }
                                            }
                                        }
                                        .onEnded { value in
                                            guard isLongPressingVoice else { return }
                                            isLongPressingVoice = false
                                            dragOffset = 0
                                            
                                            let dragDistance = abs(value.translation.height)
                                            if dragDistance > 80 {
                                                viewModel.cancelVoiceRecord()
                                                Haptics.warning()
                                            } else {
                                                viewModel.stopVoiceRecord()
                                            }
                                        }
                                    )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Camera button (right) - Telegram style
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }
    
    // MARK: - 录音UI（参考设计图）
    
    /// 录音时的完整UI - 完全参考设计图
    private var recordingVoiceUI: some View {
        HStack(spacing: 16) {
            // 左侧：红色圆形图标 + 精确时长显示（格式：0:02,84）
            HStack(spacing: 8) {
                // 红色圆形录音指示器
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 44, height: 44)
                    
                    // 内部脉冲动画效果
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .scaleEffect(viewModel.voiceService.isRecording ? 1.3 : 1.0)
                        .opacity(viewModel.voiceService.isRecording ? 0.6 : 0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: viewModel.voiceService.isRecording)
                }
                
                // 精确时长显示（分钟:秒,毫秒）
                Text(formatRecordingDuration(viewModel.voiceService.recordingDuration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .offset(x: dragOffset < -60 ? -20 : 0) // 拖动取消时向左移动
            .opacity(dragOffset < -60 ? 0.5 : 1.0) // 拖动取消时变暗
            
            Spacer()
            
            // 中间：滑动取消提示（根据拖动状态显示）
            Group {
                if dragOffset < -60 {
                    // 拖动超过阈值，显示取消状态
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                        Text("Release to cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                    }
                } else {
                    // 正常状态，显示滑动取消提示
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Slide to cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: dragOffset < -20 ? -abs(dragOffset) * 0.5 : 0) // 拖动时向左移动
                    .opacity(max(0.4, 1.0 - abs(dragOffset) / 100.0)) // 拖动时逐渐淡出
                }
            }
            .animation(.spring(response: 0.2), value: dragOffset)
            
            Spacer()
            
            // 右侧：大的蓝色麦克风按钮（激活状态）
            Button(action: {
                // 点击停止录音
                viewModel.stopVoiceRecord()
                isLongPressingVoice = false
                dragOffset = 0
            }) {
                ZStack {
                    // 主按钮
                    Circle()
                        .fill(dragOffset < -60 ? Color.red : Color.blue) // 拖动取消时变红
                        .frame(width: 56, height: 56)
                        .shadow(color: (dragOffset < -60 ? Color.red : Color.blue).opacity(0.4), radius: 8, x: 0, y: 2)
                    
                    // 光晕效果
                    Circle()
                        .fill((dragOffset < -60 ? Color.red : Color.blue).opacity(0.2))
                        .frame(width: 56, height: 56)
                        .scaleEffect(viewModel.voiceService.isRecording ? 1.4 : 1.0)
                        .opacity(viewModel.voiceService.isRecording ? 0.6 : 0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: viewModel.voiceService.isRecording)
                    
                    // 图标（取消时显示X，否则显示麦克风）
                    Image(systemName: dragOffset < -60 ? "xmark" : "mic.fill")
                        .font(.system(size: dragOffset < -60 ? 20 : 24, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isLongPressingVoice ? 1.05 : 1.0)
            .animation(.spring(response: 0.2), value: isLongPressingVoice)
            .animation(.spring(response: 0.2), value: dragOffset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard viewModel.voiceService.isRecording else { return }
                    dragOffset = value.translation.height // CGSize.height，向上为负值
                    
                    // 向上拖动超过阈值时的视觉反馈
                    if dragOffset < -80 {
                        Haptics.light()
                    }
                }
                .onEnded { value in
                    guard viewModel.voiceService.isRecording else { return }
                    let dragDistance = abs(value.translation.height)
                    
                    // 向上拖动超过阈值，取消录音
                    if dragDistance > 80 && value.translation.height < 0 {
                        viewModel.cancelVoiceRecord()
                        isLongPressingVoice = false
                        Haptics.warning()
                    } else {
                        // 正常结束录音（松开或拖动距离不够）
                        viewModel.stopVoiceRecord()
                        isLongPressingVoice = false
                    }
                    dragOffset = 0
                }
        )
    }
    
    /// 格式化录音时长（格式：0:02,84）
    private func formatRecordingDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d,%02d", minutes, seconds, milliseconds)
    }
    
    // MARK: - Helpers
    
    private func copyMessage(_ message: Message) {
        UIPasteboard.general.string = message.displayText
        Haptics.light()
        toastText = "已复制"
        showToast = true
    }
    
    private func deleteMessage(_ message: Message) {
        viewModel.deleteMessage(message)
        toastText = "已删除"
        showToast = true
    }
    
    private func findPeer(for message: Message) -> Peer? {
        // 对于系统消息，返回 nil
        guard case .user(let userId) = message.author else { return nil }
        
        // 如果是自己发送的消息，需要创建或返回自己的 peer
        if message.isOutgoing {
            // 先尝试从 peers 列表中找到
            if let selfPeer = viewModel.peers.first(where: { $0.id == viewModel.selfPeerId }) {
                return selfPeer
            }
            // 如果没有找到，创建一个包含当前用户信息的 peer
            // 使用 channelManager 的 selfPeer 信息
            let selfPeer = viewModel.channelManager.selfPeer
            return Peer(
                id: selfPeer.id,
                nickname: selfPeer.nickname,
                isHost: selfPeer.isHost,
                latitude: viewModel.locationProvider.location?.coordinate.latitude,
                longitude: viewModel.locationProvider.location?.coordinate.longitude,
                lastUpdatedAt: Date()
            )
        }
        
        // 否则查找发送者的 peer
        return viewModel.peers.first { $0.id == userId }
    }
    
    // MARK: - Time Formatting
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    // MARK: - Member Avatars Preview
    
    private var memberAvatarsPreview: some View {
        HStack(spacing: -8) {
            ForEach(Array(viewModel.peers.prefix(3).enumerated()), id: \.element.id) { index, peer in
                AvatarView(nickname: peer.nickname, size: 28)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .zIndex(Double(3 - index))
            }
            if viewModel.peers.count > 3 {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 28, height: 28)
                    Text("+\(viewModel.peers.count - 3)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                )
            }
        }
    }
}

// MARK: - Message Bubble View

private struct MessageBubbleView: View {
    let message: Message
    let peer: Peer?
    let viewModel: ChatViewModel
    let isPlaying: Bool
    let playbackProgress: Double
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onPlayVoice: () -> Void
    let onImageTap: (UIImage) -> Void
    
    private var isOutgoing: Bool { message.isOutgoing }
    private var isSystem: Bool {
        if case .system = message.author { return true }
        return false
    }
    
    var body: some View {
        if isSystem {
            systemMessageView
        } else {
            userMessageView
        }
    }
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            Text(message.displayText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var userMessageView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Avatar - 显示在左侧（接收的消息）或右侧（发送的消息）
            if !isOutgoing {
                avatarView
            }
            
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                // Nickname and metadata - 现在也显示发送的消息的昵称
                VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 2) {
                    Text(message.nickname)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    // 距离和在线时长信息
                    if let peer = peer {
                        HStack(spacing: 8) {
                            if let distanceText = viewModel.distanceText(for: peer) {
                                Label(distanceText, systemImage: "location")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let onlineDuration = viewModel.onlineDurationText(for: peer) {
                                Label(onlineDuration, systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.leading, isOutgoing ? 0 : 4)
                .padding(.trailing, isOutgoing ? 4 : 0)
                
                // Message bubble - Telegram style
                HStack(alignment: .bottom, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 6) {
                        messageContent
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Timestamp and read receipt - inside bubble, bottom right
                        HStack(spacing: 3) {
                            Text(formatTime24H(message.createdAt))
                                .font(.system(size: 12))
                                .foregroundStyle(isOutgoing ? .white.opacity(0.9) : .secondary)
                            
                            if isOutgoing {
                                // Double checkmark for read receipt - Telegram style
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .offset(x: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.bottom, 4)
                    .background(
                        Group {
                            if isOutgoing {
                                // Outgoing: Blue gradient (Telegram style)
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.33, green: 0.65, blue: 0.98),
                                        Color(red: 0.40, green: 0.55, blue: 0.95)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                // Incoming: White/Gray background (Telegram default style)
                                Color(.systemGray5)
                            }
                        }
                    )
                    .foregroundStyle(isOutgoing ? .white : .primary)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                    .overlay(alignment: .topTrailing) {
                        // Relay info overlay (if message was relayed)
                        if let hops = message.relayHops, hops > 0 {
                            RelayInfoOverlay(hops: hops, latency: message.relayLatency)
                        }
                    }
                    .contextMenu {
                        Button("复制", action: onCopy)
                        if isOutgoing {
                            Button("删除", role: .destructive, action: onDelete)
                        } else {
                            Button("举报", role: .destructive, action: onReport)
                        }
                    }
                }
            }
            
            // Avatar - 发送的消息显示在右侧
            if isOutgoing {
                avatarView
            }
        }
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
    }
    
    private var avatarView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(message.nickname.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
            )
    }
    
    @ViewBuilder
    private var messageContent: some View {
        if let messageType = message.messageType {
            switch messageType {
            case .text(let text), .emoji(let text):
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            case .image(let data):
                if let uiImage = UIImage(data: data) {
                    Button(action: {
                        onImageTap(uiImage)
                    }) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250, maxHeight: 250)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("📷 图片")
                }
            case .voice(_, let duration):
                VoiceMessageView(
                    message: message,
                    isPlaying: isPlaying,
                    progress: playbackProgress,
                    duration: duration,
                    onPlay: onPlayVoice
                )
                .frame(maxWidth: 220) // 限制语音消息气泡宽度
            case .video(let data, let thumbnail, let duration):
                // 显示视频缩略图或占位符
                if let thumbnailData = thumbnail, let thumbnailImage = UIImage(data: thumbnailData) {
                    VStack(spacing: 4) {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250, maxHeight: 250)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.8))
                            )
                        if let duration = duration {
                            Text("🎥 视频 (\(duration)秒)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("🎥 视频")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // 没有缩略图，显示占位符
                    VStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .frame(width: 100, height: 100)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        Text("🎥 视频")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let attachment = message.attachment,
                  let data = Data(base64Encoded: attachment.dataBase64),
                  let uiImage = UIImage(data: data) {
            // Legacy attachment support
            Button(action: {
                onImageTap(uiImage)
            }) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250, maxHeight: 250)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        } else if !message.text.isEmpty {
            Text(message.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("未知消息类型")
                .foregroundStyle(.secondary)
        }
    }
    
    // 24小时制时间格式化
    private func formatTime24H(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

private struct Err: Identifiable {
    let id: UUID
    let message: String
}

private struct MembersSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var toKick: UUID? = nil
    
    /// 获取所有应该显示的成员（包括房主）
    private var allMembers: [Peer] {
        var members = viewModel.peers
        
        // 如果 peers 为空或没有房主，确保包含房主信息
        let hostPeer = viewModel.getHostPeer()
        if let host = hostPeer {
            // 如果房主不在 peers 列表中，添加房主
            if !members.contains(where: { $0.id == host.id }) {
                members.insert(host, at: 0) // 房主放在最前面
            }
        }
        
        // 如果仍然为空且当前用户是房主，至少显示自己
        if members.isEmpty {
            let selfPeer = viewModel.channelManager.selfPeer
            members.append(Peer(
                id: selfPeer.id,
                nickname: selfPeer.nickname,
                isHost: selfPeer.isHost,
                latitude: viewModel.locationProvider.location?.coordinate.latitude,
                longitude: viewModel.locationProvider.location?.coordinate.longitude,
                lastUpdatedAt: Date()
            ))
        }
        
        return members
    }

    var body: some View {
        NavigationStack {
            if allMembers.isEmpty {
                // 空状态（理论上不应该出现）
                VStack(spacing: 16) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无成员")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("成员")
            } else {
                List(allMembers) { peer in
                    HStack(spacing: 12) {
                        // 随机头像
                        AvatarView(nickname: peer.nickname, size: 44)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(peer.nickname)
                                    .font(.headline)
                                if peer.isHost {
                                    Text("房主")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .cornerRadius(4)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                // 距离
                                if let distanceText = viewModel.distanceText(for: peer) {
                                    Label(distanceText, systemImage: "location")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                // 在线时长
                                if let onlineDuration = viewModel.onlineDurationText(for: peer) {
                                    Label(onlineDuration, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let bearingText = viewModel.bearingText(for: peer) {
                                    Text(bearingText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if peer.isHost == false && viewModel.isHost {
                            Button(role: .destructive) {
                                toKick = peer.id
                                viewModel.kick(peer.id)
                            } label: { Text("踢出") }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle("成员 (\(allMembers.count))")
            }
        }
    }
}

// MARK: - Avatar View Helper

private struct AvatarView: View {
    let nickname: String
    let size: CGFloat
    
    private var avatarColor: Color {
        // 根据昵称生成稳定的随机颜色
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

// MARK: - Previews

// MARK: - Supporting Types

private struct ImageViewerItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ChatView_Previews: PreviewProvider {
    static var previewMessages: [Message] {
        let channelId = UUID()
        let now = Date()
        let calendar = Calendar.current
        
        return [
            // System message
            Message(
                channelId: channelId,
                author: .system,
                nickname: "系统",
                text: "欢迎加入 数字游民频道",
                createdAt: calendar.date(byAdding: .minute, value: -30, to: now) ?? now
            ),
            
            // Incoming messages
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "Alice",
                text: "",
                messageType: .text("早上好！"),
                isOutgoing: false,
                createdAt: calendar.date(byAdding: .minute, value: -25, to: now) ?? now
            ),
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "Bob",
                text: "",
                messageType: .text("发送一个骰子表情来投掷骰子！🎲"),
                isOutgoing: false,
                createdAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now
            ),
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "Alice",
                text: "",
                messageType: .text("推进到伊利诺伊大道。如果你经过起点，收集咖啡 😋"),
                isOutgoing: false,
                createdAt: calendar.date(byAdding: .minute, value: -15, to: now) ?? now
            ),
            
            // Outgoing messages
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "我",
                text: "",
                messageType: .emoji("🎲"),
                isOutgoing: true,
                createdAt: calendar.date(byAdding: .minute, value: -12, to: now) ?? now
            ),
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "我",
                text: "",
                messageType: .text("通过了！🎉"),
                isOutgoing: true,
                createdAt: calendar.date(byAdding: .minute, value: -10, to: now) ?? now
            ),
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "我",
                text: "",
                messageType: .text("好的"),
                isOutgoing: true,
                createdAt: calendar.date(byAdding: .minute, value: -5, to: now) ?? now
            ),
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "我",
                text: "",
                messageType: .text("在那里等我。"),
                isOutgoing: true,
                createdAt: calendar.date(byAdding: .minute, value: -2, to: now) ?? now
            ),
            
            // Voice message (incoming)
            Message(
                channelId: channelId,
                author: .user(UUID()),
                nickname: "Charlie",
                text: "",
                messageType: .voice(Data(), duration: 23),
                isOutgoing: false,
                createdAt: calendar.date(byAdding: .minute, value: -1, to: now) ?? now
            )
        ]
    }
    
    static var previewPeers: [Peer] {
        [
            Peer(nickname: "Alice", isHost: false),
            Peer(nickname: "Bob", isHost: false),
            Peer(nickname: "Charlie", isHost: false)
        ]
    }
    
    static var previews: some View {
        Group {
            // Light mode preview
            NavigationStack {
                ChatView(
                    channel: Channel(name: "数字游民", hostPeerId: UUID()),
                    channelManager: nil
                )
            }
            .previewDisplayName("Light Mode")
            .preferredColorScheme(.light)
            
            // Dark mode preview
            NavigationStack {
                let previewVM = ChatViewModel(
                    channel: Channel(name: "数字游民", hostPeerId: UUID()),
                    previewMessages: previewMessages,
                    previewPeers: previewPeers
                )
                ChatViewPreviewWrapper(viewModel: previewVM)
            }
            .previewDisplayName("Dark Mode with Sample Messages")
            .preferredColorScheme(.dark)
            
            // iPhone SE preview
            NavigationStack {
                let previewVM = ChatViewModel(
                    channel: Channel(name: "数字游民", hostPeerId: UUID()),
                    previewMessages: previewMessages,
                    previewPeers: previewPeers
                )
                ChatViewPreviewWrapper(viewModel: previewVM)
            }
            .previewDisplayName("iPhone SE")
            .preferredColorScheme(.light)
            .previewDevice("iPhone SE (3rd generation)")
        }
    }
}

// Wrapper to use preview ViewModel
private struct ChatViewPreviewWrapper: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    private func findPeer(for message: Message) -> Peer? {
        guard case .user(let userId) = message.author else { return nil }
        if message.isOutgoing {
            if let selfPeer = viewModel.peers.first(where: { $0.id == viewModel.selfPeerId }) {
                return selfPeer
            }
            let selfPeer = viewModel.channelManager.selfPeer
            return Peer(
                id: selfPeer.id,
                nickname: selfPeer.nickname,
                isHost: selfPeer.isHost,
                latitude: viewModel.locationProvider.location?.coordinate.latitude,
                longitude: viewModel.locationProvider.location?.coordinate.longitude,
                lastUpdatedAt: Date()
            )
        }
        return viewModel.peers.first { $0.id == userId }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Chats")
                            .font(.system(size: 17, weight: .regular))
                    }
                    .foregroundStyle(Color.blue)
                }
                
                Spacer()
                
                VStack(spacing: 1) {
                    Text(viewModel.channel.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if !viewModel.peers.isEmpty {
                        Text("\(viewModel.peers.count) 成员")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(viewModel.channel.name.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color(.separator)),
                alignment: .bottom
            )
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                peer: findPeer(for: message),
                                viewModel: viewModel,
                                isPlaying: false,
                                playbackProgress: 0.0,
                                onCopy: {},
                                onDelete: {},
                                onReport: {},
                                onPlayVoice: {},
                                onImageTap: { _ in }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    if let last = viewModel.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input bar
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
                
                HStack(spacing: 8) {
                    TextField("Message", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .disabled(true)
                }
                .frame(maxWidth: .infinity)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(Divider(), alignment: .top)
        }
        .navigationBarHidden(true)
    }
}

