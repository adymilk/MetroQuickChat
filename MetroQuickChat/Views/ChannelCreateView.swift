import SwiftUI

@MainActor
struct ChannelCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = RandomChannelName.generate()
    let nickname: String
    @State private var createdChannel: Channel? = nil
    @State private var manager: ChannelManager? = nil
    // 可选：如果从 ChannelListView 调用，可以传入共享的 manager
    var existingManager: ChannelManager? = nil

    var body: some View {
        Form {
            Section("频道信息") {
                TextField("频道名称", text: $name)
            }
            Section {
                Button("创建") { create() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("创建频道")
        .navigationDestination(item: Binding(
            get: { createdChannel },
            set: { createdChannel = $0 }
        )) { channel in
            if let mgr = manager {
                ChatView(channel: channel, channelManager: mgr)
            }
        }
    }

    private func create() {
        // 如果传入了共享的 manager，使用它；否则创建新的
        let mgr: ChannelManager
        if let existing = existingManager {
            mgr = existing
            // 使用共享的 manager，selfPeer 已经在 HomeView 中正确初始化
        } else {
            let peer = Peer(nickname: nickname, isHost: true)
            mgr = ChannelManager(central: BluetoothCentralManager(), peripheral: BluetoothPeripheralManager(), selfPeer: peer)
        }
        
        mgr.createChannel(name: name)
        
        // 延迟设置状态，避免在视图更新期间修改
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒延迟
            mgr.advertiseChannel()
            self.manager = mgr
            self.createdChannel = mgr.currentChannel
            // 不需要dismiss，直接跳转到ChatView
            // ChatView的返回按钮会自动返回到首页
        }
    }
}

struct ChannelCreateView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ChannelCreateView(nickname: "预览用户") }
    }
}


