import SwiftUI
import CoreLocation
import Combine

@MainActor
class RadarScanViewModel: ObservableObject {
    @Published var channels: [ChannelTarget] = []
    @Published var selectedChannel: ChannelTarget? = nil
    @Published var isScanning: Bool = false
    let myLocation: CLLocationCoordinate2D
    let channelManager: ChannelManager
    private var scanTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var previousChannelIds: Set<UUID> = []
    private let notificationService = NotificationService.shared

    struct ChannelTarget: Identifiable, Equatable {
        let id: UUID
        let channel: Channel
        let name: String
        let distance: Double // 米
        let bearing: Double  // 方位角 (度)
        let direction: String
    }

    init(channelManager: ChannelManager? = nil, nickname: String = "") {
        if let manager = channelManager {
            self.channelManager = manager
        } else {
            let peer = Peer(nickname: nickname.isEmpty ? "用户" : nickname)
            self.channelManager = ChannelManager(
                central: BluetoothCentralManager(),
                peripheral: BluetoothPeripheralManager(),
                selfPeer: peer
            )
        }
        // 尽快获取位置信息
        let loc: CLLocationCoordinate2D = self.channelManager.locationProvider.location?.coordinate ?? CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
        self.myLocation = loc
        // 绑定事件监听
        self.channelManager.events.sink { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .channelsUpdated, .peersUpdated:
                self.refreshTargets()
            default: break
            }
        }.store(in: &cancellables)
        
        // 监听频道列表变化，检测新频道
        self.channelManager.$channels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newChannels in
                self?.checkForNewChannels(newChannels)
                self?.refreshTargets()
            }
            .store(in: &cancellables)
    }
    func start() { scan() }
    func stop() { 
        scanTimer?.invalidate()
        scanTimer = nil
        // 注意：不停止 channelManager 的扫描，因为它可能在其他页面使用
        // 只在 RadarScanView 自己的定时器停止
    }

    private func scan() {
        scanTimer?.invalidate()
        isScanning = true
        
        // 确保 ChannelManager 正在扫描（但不重复启动）
        // 如果已经在扫描，不会重复启动（BluetoothCentralManager 内部会检查）
        channelManager.startDiscovery()
        
        // 每0.5秒更新目标列表
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self.refreshTargets()
                // 如果扫描了一段时间还没有频道，停止扫描指示
                if !self.channels.isEmpty {
                    self.isScanning = false
                }
            }
        }
    }
    
    private func refreshTargets() {
        let loc = channelManager.locationProvider.location?.coordinate ?? myLocation
        let allPeers = channelManager.peers
        let discoveredChannels = channelManager.channels
        
        guard !discoveredChannels.isEmpty else {
            channels = []
            return
        }
        
        let list = discoveredChannels.compactMap { ch -> ChannelTarget? in
            // 尝试从 peers 找房主，或从 discoveryId 关联
            var hostPeer: Peer? = allPeers.first(where: { $0.id == ch.hostPeerId })
            // 如果没有找到，从所有 peers 中找 isHost 的
            if hostPeer == nil {
                hostPeer = allPeers.first(where: { $0.isHost })
            }
            // 如果仍然没有，使用伪随机位置显示在雷达上（等待 Presence 更新）
            if let plat = hostPeer?.latitude, let plon = hostPeer?.longitude {
                let cl = CLLocation(latitude: plat, longitude: plon)
                let me = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                let dist = me.distance(from: cl)
                guard dist.isFinite && dist >= 0 else { return nil }
                let bearing = Self.bearing(from: loc, to: CLLocationCoordinate2D(latitude: plat, longitude: plon))
                let direction = Self.directionLabel(for: bearing)
                return ChannelTarget(id: ch.id, channel: ch, name: ch.name, distance: dist, bearing: bearing, direction: direction)
            } else {
                // 临时显示：基于 channel id 的伪随机位置，距离显示为"附近"
                var hasher = Hasher()
                hasher.combine(ch.id)
                let hash = abs(hasher.finalize())
                let bearing = Double(hash % 360)
                let direction = Self.directionLabel(for: bearing)
                // 使用合理的距离范围（10-50米）
                let distance = 10.0 + Double(hash % 40)
                return ChannelTarget(id: ch.id, channel: ch, name: ch.name, distance: distance, bearing: bearing, direction: direction)
            }
        }
        
        channels = list.sorted { $0.distance < $1.distance }
    }
    func join(channel: ChannelTarget) { channelManager.joinChannel(channel.channel); selectedChannel = channel }
    
    /// 检测新频道并触发提示和通知
    private func checkForNewChannels(_ newChannels: [Channel]) {
        let currentChannelIds = Set(newChannels.map { $0.id })
        
        // 找出新发现的频道（不在之前的列表中）
        let newChannelsFound = newChannels.filter { !previousChannelIds.contains($0.id) }
        
        if !newChannelsFound.isEmpty {
            print("RadarScanViewModel: 发现 \(newChannelsFound.count) 个新频道")
            
            // 触发震动反馈
            Haptics.success()
            
            // 发送通知
            for channel in newChannelsFound {
                notificationService.notifyChannelDiscovered(channel)
            }
        }
        
        // 更新已发现的频道ID集合
        previousChannelIds = currentChannelIds
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brng = atan2(y, x) * 180 / .pi
        if brng < 0 { brng += 360 }
        return brng
    }
    private static func directionLabel(for degree: Double) -> String {
        let dirs = ["北", "东北", "东", "东南", "南", "西南", "西", "西北", "北"]
        let idx = Int((degree + 22.5) / 45.0)
        return dirs[min(max(idx, 0), 8)]
    }
}

struct RadarScanView: View {
    @StateObject private var vm: RadarScanViewModel
    @State private var angle: Double = 0
    @State private var pushToChat: Channel? = nil
    @State private var highlightId: UUID? = nil
    @State private var scanProgress: Double = 0.0

    init(nickname: String, channelManager: ChannelManager? = nil) {
        _vm = StateObject(wrappedValue: RadarScanViewModel(channelManager: channelManager, nickname: nickname))
    }

    var body: some View {
        ZStack {
            // 背景渐变（高科技感）
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.15, blue: 0.25),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 雷达显示区域
                radarDisplay
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // 状态和信息区域
                VStack(spacing: 16) {
                    channelStatusText
                        .padding(.top, 20)
                    
                    // 扫描进度指示器
                    if vm.isScanning {
                        scanningIndicator
                    }
                    
                    // 频道列表（如果有）
                    if !vm.channels.isEmpty {
                        channelListMini
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("雷达扫描")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    vm.start()
                    angle = 0
                    withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                    Haptics.light()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            angle = 0
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                angle = 360
            }
            // 延迟一点再启动，避免与其他页面冲突
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                vm.start()
            }
        }
        .onDisappear {
            // 只停止雷达扫描的定时器，不停止 ChannelManager 的扫描
            // 因为 ChannelManager 可能在首页等其他地方还在使用
            vm.stop()
        }
        .onChange(of: vm.selectedChannel) { oldValue, newValue in
            if let ch = newValue?.channel {
                pushToChat = ch
            }
        }
        .navigationDestination(item: $pushToChat) { ch in
            ChatView(channel: ch, channelManager: vm.channelManager)
        }
    }
    
    private var radarDisplay: some View {
        GeometryReader { proxy in
            let safeSize = max(proxy.size.width, proxy.size.height, 200)
            let size = min(safeSize, proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width/2, y: proxy.size.height/2)
            let radius = max(size/2 - 32, 50) // 确保 radius 至少为 50
            
            ZStack {
                // 雷达背景（科技感网格）
                radarBackground(radius: radius, center: center)
                
                // 雷达环
                radarRings(radius: radius, center: center)
                
                // 中心点
                radarCenterPoint(center: center)
                
                // 扫描线
                RadarSweep(angle: angle, radius: radius, center: center)
                    .frame(width: radius * 2 + 100, height: radius * 2 + 100)
                    .position(center)
                
                // 频道目标
                channelTargets(radius: radius, center: center)
                
                // 方位指示器（N, E, S, W）
                directionMarkers(radius: radius, center: center)
            }
        }
    }
    
    private func radarBackground(radius: CGFloat, center: CGPoint) -> some View {
        ZStack {
            // 外层光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(0.15),
                            Color.blue.opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: radius * 0.3,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2 + 60, height: radius * 2 + 60)
                .position(center)
            
            // 主背景（网格风格）
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.1, green: 0.2, blue: 0.3).opacity(0.6),
                            Color(red: 0.05, green: 0.1, blue: 0.2).opacity(0.8),
                            Color.black.opacity(0.9)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .overlay(
                    // 网格线
                    Path { path in
                        // 水平线
                        for i in 1..<4 {
                            let y = center.y - radius + CGFloat(i) * radius * 2 / 4
                            path.move(to: CGPoint(x: center.x - radius, y: y))
                            path.addLine(to: CGPoint(x: center.x + radius, y: y))
                        }
                        // 垂直线
                        for i in 1..<4 {
                            let x = center.x - radius + CGFloat(i) * radius * 2 / 4
                            path.move(to: CGPoint(x: x, y: center.y - radius))
                            path.addLine(to: CGPoint(x: x, y: center.y + radius))
                        }
                        // 对角线
                        path.move(to: CGPoint(x: center.x - radius, y: center.y - radius))
                        path.addLine(to: CGPoint(x: center.x + radius, y: center.y + radius))
                        path.move(to: CGPoint(x: center.x - radius, y: center.y + radius))
                        path.addLine(to: CGPoint(x: center.x + radius, y: center.y - radius))
                    }
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 0.5)
                )
                .clipShape(Circle())
        }
    }
    
    private func radarRings(radius: CGFloat, center: CGPoint) -> some View {
        ForEach(1..<5) { i in
            let ringRadius = radius * CGFloat(i) / 4
            AnimatedRing(
                ringRadius: ringRadius,
                center: center,
                delay: Double(i) * 0.1,
                isOuterRing: i == 4
            )
        }
    }
    
    private func radarCenterPoint(center: CGPoint) -> some View {
        ZStack {
            // 外圈脉冲
            Circle()
                .stroke(Color.cyan.opacity(0.4), lineWidth: 2)
                .frame(width: 40, height: 40)
                .position(center)
                .opacity(0.6)
            
            // 中圈
            Circle()
                .stroke(Color.cyan, lineWidth: 2)
                .frame(width: 28, height: 28)
                .position(center)
            
            // 中心点
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 16, height: 16)
                .position(center)
                .shadow(color: .cyan, radius: 8)
        }
    }
    
    private func directionMarkers(radius: CGFloat, center: CGPoint) -> some View {
        ZStack {
            ForEach(["N", "E", "S", "W"].enumerated().map { $0 }, id: \.offset) { item in
                let angle = Double(item.offset) * 90.0 - 90.0
                let theta = angle * .pi / 180.0
                let x = center.x + (radius - 20) * CGFloat(sin(theta))
                let y = center.y - (radius - 20) * CGFloat(cos(theta))
                
                Text(item.element)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cyan.opacity(0.8))
                    .position(x: x, y: y)
            }
        }
    }
    
    private func channelTargets(radius: CGFloat, center: CGPoint) -> some View {
        ForEach(vm.channels) { ch in
            ChannelTargetView(
                channel: ch,
                radius: radius,
                center: center,
                highlightId: $highlightId
            ) {
                vm.join(channel: ch)
            }
        }
    }
    
    private var channelStatusText: some View {
        VStack(spacing: 12) {
            if vm.channels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: vm.isScanning ? "dot.radiowaves.left.and.right" : "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(vm.isScanning ? Color.cyan : Color.gray)
                        .symbolEffect(.pulse, isActive: vm.isScanning)
                    
                    Text(vm.isScanning ? "正在扫描..." : "未发现频道")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("靠近其他设备或刷新重试")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.gray)
                }
                .padding(.top, 20)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    
                    Text("发现 \(vm.channels.count) 个频道")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    private var scanningIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(0.8)
            Text("扫描中...")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.cyan.opacity(0.1))
        )
    }
    
    private var channelListMini: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.channels.prefix(5)) { target in
                    Button(action: {
                        vm.join(channel: target)
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                            
                            Text(target.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            
                            Text("\(Int(target.distance))m · \(target.direction)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.cyan.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct RadarSweep: View {
    let angle: Double
    let radius: CGFloat
    let center: CGPoint
    
    var body: some View {
        GeometryReader { geometry in
            let localCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // 主扫描线（更宽更亮）- 从中心点向上绘制
                Path { path in
                    path.move(to: localCenter)
                    path.addLine(to: CGPoint(
                        x: localCenter.x,
                        y: localCenter.y - radius
                    ))
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.9),
                            Color.cyan.opacity(0.6),
                            Color.cyan.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0.5),
                        endPoint: UnitPoint(x: 0.5, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(angle), anchor: .center)
                .shadow(color: .cyan, radius: 8)
                
                // 扫描尾迹效果
                ForEach(0..<6) { i in
                    let trailAngle = angle - Double(i) * 2
                    let alpha = 1.0 - Double(i) * 0.15
                    Path { path in
                        path.move(to: localCenter)
                        path.addLine(to: CGPoint(
                            x: localCenter.x,
                            y: localCenter.y - radius
                        ))
                    }
                    .stroke(Color.cyan.opacity(alpha * 0.3), lineWidth: 1)
                    .rotationEffect(.degrees(trailAngle), anchor: .center)
                }
            }
        }
    }
}

private struct ChannelTargetView: View {
    let channel: RadarScanViewModel.ChannelTarget
    let radius: CGFloat
    let center: CGPoint
    @Binding var highlightId: UUID?
    let onJoin: () -> Void
    
    var body: some View {
        let maxDisplayDist: Double = 100.0 // 最大显示距离100米
        let displayDist = min(channel.distance, maxDisplayDist)
        let normalizedDist = displayDist / maxDisplayDist
        let pointRadius = radius * CGFloat(0.2 + 0.6 * normalizedDist) // 20%-80%半径范围
        
        // 确保 pointRadius 在有效范围内
        let safeRadius = max(min(pointRadius, radius * 0.9), radius * 0.15)
        
        let theta = channel.bearing * .pi / 180.0
        let pt = CGPoint(
            x: center.x + safeRadius * CGFloat(sin(theta)),
            y: center.y - safeRadius * CGFloat(cos(theta))
        )
        
        // 确保坐标在有效范围内
        guard pt.x.isFinite && pt.y.isFinite && pt.x > 0 && pt.y > 0 else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            ZStack {
                // 脉冲效果
                TargetPulse(isActive: highlightId == channel.id)
                    .position(pt)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            highlightId = channel.id
                        }
                    }
                
                // 目标点
                Button(action: {
                    Haptics.light()
                    onJoin()
                }) {
                    ZStack {
                        // 外圈光晕
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(0.4),
                                        Color.green.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 12
                                )
                            )
                            .frame(width: 24, height: 24)
                        
                        // 中心点
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: .green, radius: 4)
                    }
                }
                .buttonStyle(.plain)
                .position(pt)
            }
        )
    }
}

private struct TargetPulse: View {
    let isActive: Bool
    @State private var animate = false
    
    var body: some View {
        ZStack {
            if isActive {
                // 多圈脉冲效果
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.5 - Double(i) * 0.15), lineWidth: 1.5)
                        .frame(width: 20 + CGFloat(i) * 8, height: 20 + CGFloat(i) * 8)
                        .scaleEffect(animate ? 2.0 + CGFloat(i) * 0.5 : 1.0)
                        .opacity(animate ? 0.0 : 0.6)
                }
            }
        }
        .onAppear {
            if isActive {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
        }
    }
}

// 带动画闪烁效果的雷达环
private struct AnimatedRing: View {
    let ringRadius: CGFloat
    let center: CGPoint
    let delay: Double
    let isOuterRing: Bool
    @State private var isFlashing: Bool = false
    
    var body: some View {
        ZStack {
            // 基础圆圈（正常状态）
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.6),
                            Color.cyan.opacity(0.3),
                            Color.cyan.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .opacity(isFlashing ? 0.3 : 1.0)
            
            // 高亮闪烁圆圈
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(1.0),
                            Color.cyan.opacity(0.8),
                            Color.cyan.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, dash: [4, 4])
                )
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .opacity(isFlashing ? 1.0 : 0.0)
                .shadow(color: .cyan.opacity(0.8), radius: 4)
            
            // 距离标签
            if isOuterRing {
                Text("\(Int(ringRadius / 100))0m")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.6))
                    .offset(x: ringRadius + 20, y: 0)
            }
        }
        .position(center)
        .onAppear {
            // 延迟后开始闪烁动画
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // 每秒闪烁一次（1秒一个周期：0.1秒亮，0.9秒暗）
                withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: false).delay(0.9)) {
                    isFlashing = true
                }
            }
        }
        .onChange(of: isFlashing) { newValue in
            if newValue {
                // 闪烁后快速恢复
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isFlashing = false
                    }
                    // 等待0.9秒后再次闪烁
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isFlashing = true
                    }
                }
            }
        }
    }
}



