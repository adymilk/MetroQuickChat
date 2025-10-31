import SwiftUI

/// 独立的聊天界面演示视图，用于在单台设备上测试Telegram风格的UI
@MainActor
struct ChatViewDemo: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DemoChatViewModel
    @State private var selectedImage: UIImage? = nil
    
    init() {
        let channel = Channel(name: "数字游民", hostPeerId: UUID())
        _viewModel = StateObject(wrappedValue: DemoChatViewModel(channel: channel))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - Telegram style
            chatHeader
            
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.messages) { message in
                            DemoMessageBubbleView(
                                message: message,
                                isPlaying: viewModel.playingVoiceId == message.id,
                                playbackProgress: viewModel.voicePlaybackProgress,
                                onCopy: { copyMessage(message) },
                                onDelete: { deleteMessage(message) },
                                onReport: {},
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input bar - Telegram style
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(viewModel.channel.name)
                        .font(.headline)
                    Text("\(viewModel.peers.count) 成员")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(item: imageViewerBinding) { item in
            ImageViewer(image: item.image)
        }
    }
    
    private var imageViewerBinding: Binding<ImageViewerItem?> {
        Binding(
            get: { selectedImage.map { ImageViewerItem(image: $0) } },
            set: { selectedImage = $0?.image }
        )
    }
    
    // MARK: - Header
    
    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Back button - Telegram style (blue chevron + "Chats")
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
            
            // Channel info in center - Telegram style
            VStack(spacing: 1) {
                Text(viewModel.channel.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("\(viewModel.peers.count) 成员")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Channel avatar on right - Telegram style circular
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
    }
    
    // MARK: - Input Bar
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    private var inputBar: some View {
        HStack(spacing: 8) {
            // Attachment button (left) - Telegram style paperclip
            Button(action: {
                // Demo: Add a system message
                viewModel.addSystemMessage("点击了附件按钮（演示）")
            }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
            }
            
            // Text input - Telegram style (always visible)
            HStack(spacing: 6) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                
                // Show send button when text exists, otherwise show voice button
                if !inputText.isEmpty {
                    Button(action: {
                        viewModel.sendText(inputText)
                        inputText = ""
                        isInputFocused = false
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                } else {
                    // Voice button
                    Button(action: {
                        viewModel.addSystemMessage("点击了语音按钮（演示）")
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Camera button (right) - Telegram style
            Button(action: {
                viewModel.addSystemMessage("点击了相机按钮（演示）")
            }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }
    
    // MARK: - Helpers
    
    private func copyMessage(_ message: Message) {
        UIPasteboard.general.string = message.displayText
    }
    
    private func deleteMessage(_ message: Message) {
        viewModel.deleteMessage(message)
    }
}

// MARK: - Demo ViewModel

@MainActor
class DemoChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var peers: [Peer] = []
    @Published var playingVoiceId: UUID? = nil
    @Published var voicePlaybackProgress: Double = 0.0
    
    let channel: Channel
    
    init(channel: Channel) {
        self.channel = channel
        setupDemoData()
    }
    
    private func setupDemoData() {
        let channelId = channel.id
        let now = Date()
        let calendar = Calendar.current
        
        // Add peers
        peers = [
            Peer(nickname: "Alice", isHost: false),
            Peer(nickname: "Bob", isHost: false),
            Peer(nickname: "Charlie", isHost: false)
        ]
        
        // Add demo messages
        messages = [
            // System message
            Message(
                channelId: channelId,
                author: .system,
                nickname: "系统",
                text: "欢迎加入 \(channel.name)",
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
    
    func sendText(_ text: String) {
        let message = Message(
            channelId: channel.id,
            author: .user(UUID()),
            nickname: "我",
            text: "",
            messageType: .text(text),
            isOutgoing: true,
            createdAt: Date()
        )
        messages.append(message)
    }
    
    func addSystemMessage(_ text: String) {
        let message = Message(
            channelId: channel.id,
            author: .system,
            nickname: "系统",
            text: text,
            createdAt: Date()
        )
        messages.append(message)
    }
    
    func deleteMessage(_ message: Message) {
        messages.removeAll { $0.id == message.id }
    }
    
    func playVoice(message: Message) {
        playingVoiceId = message.id
        // Simulate playback progress
        voicePlaybackProgress = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.playingVoiceId == message.id {
                self.voicePlaybackProgress += 0.05
                if self.voicePlaybackProgress >= 1.0 {
                    self.voicePlaybackProgress = 0.0
                    self.playingVoiceId = nil
                    timer.invalidate()
                }
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Demo Message Bubble View

private struct DemoMessageBubbleView: View {
    let message: Message
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
            if !isOutgoing {
                avatarView
            }
            
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                if !isOutgoing {
                    nicknameView
                }
                
                messageBubble
            }
        }
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
    }
    
    private var nicknameView: some View {
        Text(message.nickname)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
    
    private var messageBubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                messageContent
                    .fixedSize(horizontal: false, vertical: true)
                
                timestampView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
            .background(messageBubbleBackground)
            .foregroundStyle(isOutgoing ? .white : .primary)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
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
    
    private var timestampView: some View {
        HStack(spacing: 3) {
            Text(message.createdAt, style: .time)
                .font(.system(size: 12))
                .foregroundStyle(isOutgoing ? .white.opacity(0.9) : .secondary)
            
            if isOutgoing {
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
    
    @ViewBuilder
    private var messageBubbleBackground: some View {
        if isOutgoing {
            LinearGradient(
                colors: [
                    Color(red: 0.33, green: 0.65, blue: 0.98),
                    Color(red: 0.40, green: 0.55, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.systemGray5)
        }
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
            case .voice(let data, let duration):
                VoiceMessageView(
                    message: message,
                    isPlaying: isPlaying,
                    progress: playbackProgress,
                    duration: duration,
                    onPlay: onPlayVoice
                )
            }
        } else if !message.text.isEmpty {
            Text(message.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("未知消息类型")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Supporting Types

private struct ImageViewerItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Preview

struct ChatViewDemo_Previews: PreviewProvider {
    static var previews: some View {
        ChatViewDemo()
            .preferredColorScheme(.light)
        
        ChatViewDemo()
            .preferredColorScheme(.dark)
    }
}
