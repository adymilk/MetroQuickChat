import SwiftUI

@MainActor
struct HomeView: View {
    @State private var nickname: String = UserDefaults.standard.string(forKey: "nickname") ?? RandomNickname.generate()
    @State private var showCreateChannel: Bool = false
    
    // 共享的 ChannelManager 实例，确保数据一致性
    // 使用 lazy 初始化，在 nickname 确定后再创建
    @StateObject private var sharedChannelManager: ChannelManager = {
        let defaultNickname = UserDefaults.standard.string(forKey: "nickname") ?? RandomNickname.generate()
        let peer = Peer(nickname: defaultNickname)
        return ChannelManager(
            central: BluetoothCentralManager(),
            peripheral: BluetoothPeripheralManager(),
            selfPeer: peer
        )
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("地铁快打")
                                .font(.largeTitle.bold())
                            Text("你好，\(nickname)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { presentEditNickname() } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                        }
                    }

                    NavigationLink {
                        ChannelListView(nickname: nickname, sharedManager: sharedChannelManager)
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("附近频道")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink { ChannelCreateView(nickname: nickname, existingManager: sharedChannelManager) } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("创建频道")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink {
                        ChannelMapView(nickname: nickname, sharedManager: sharedChannelManager)
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("附近地图模式")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    HotChannelsRow(nickname: nickname, sharedManager: sharedChannelManager)
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView(channelManager: sharedChannelManager)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                    
                    NavigationLink {
                        FavoriteChannelsView(nickname: nickname, channelManager: sharedChannelManager)
                    } label: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                FloatingActionButton(action: { 
                    showCreateChannel = true
                    Haptics.light()
                }) { 
                    Image(systemName: "plus") 
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .navigationDestination(isPresented: $showCreateChannel) {
                ChannelCreateView(nickname: nickname, existingManager: sharedChannelManager)
            }
        }
        .onAppear { 
            saveNicknameIfNeeded()
            // 启动扫描，并自动尝试加入收藏频道
            sharedChannelManager.startDiscovery()
            // 延迟一下，等待扫描到频道
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                sharedChannelManager.autoJoinFavoriteChannels()
            }
        }
        .onChange(of: nickname) { newNickname in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func presentEditNickname() {
        let alert = UIAlertController(title: "昵称", message: "请输入昵称", preferredStyle: .alert)
        alert.addTextField { $0.text = nickname }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let text = alert.textFields?.first?.text, text.isEmpty == false {
                nickname = text
                UserDefaults.standard.set(text, forKey: "nickname")
                // 同步更新 sharedChannelManager 的昵称
                sharedChannelManager.updateNickname(text)
                Haptics.success()
            }
        })
        UIApplication.shared.topMostController()?.present(alert, animated: true)
    }

    private func saveNicknameIfNeeded() {
        if UserDefaults.standard.string(forKey: "nickname") == nil {
            UserDefaults.standard.set(nickname, forKey: "nickname")
        }
    }
}

private enum RandomNickname {
    static func generate() -> String {
        let animals = ["熊猫", "猎豹", "海豚", "北极狐", "火烈鸟", "猫头鹰", "狮子", "鲸鱼"]
        let adj = ["迅捷", "低调", "勇敢", "机智", "冷静", "快乐", "神秘", "自由"]
        return "\(adj.randomElement()!)\(animals.randomElement()!)\(Int.random(in: 100...999))"
    }
}

private extension UIApplication {
    func topMostController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topMostController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return tab.selectedViewController.flatMap { topMostController(base: $0) } }
        if let presented = base?.presentedViewController { return topMostController(base: presented) }
        return base
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .preferredColorScheme(.dark)
        HomeView()
            .preferredColorScheme(.light)
            .previewDevice("iPad (10th generation)")
    }
}


