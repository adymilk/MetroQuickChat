import SwiftUI
import MapKit

@MainActor
struct ChannelMapView: View {
    @StateObject private var locationProvider = LocationProvider()
    @StateObject private var viewModel: ChannelListViewModel
    @State private var pushToChat: Channel? = nil
    @State private var isScanning = false
    @State private var annotations: [ChannelAnnotation] = []

    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))

    init(nickname: String, sharedManager: ChannelManager? = nil) {
        let manager = sharedManager ?? ChannelManager(central: BluetoothCentralManager(), peripheral: BluetoothPeripheralManager(), selfPeer: Peer(nickname: nickname))
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(channelManager: manager, defaultNickname: nickname))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, annotationItems: annotations) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    Button(action: {
                        Haptics.light()
                        viewModel.join(channel: item.channel)
                    }) {
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 状态提示卡片
            VStack(spacing: 8) {
                if annotations.isEmpty {
                    VStack(spacing: 8) {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("正在扫描附近频道...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "map.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("附近地图模式")
                                .font(.headline)
                            Text("在此模式下，发现的频道会显示在地图上")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text("点击地图上的标注可以加入频道")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                } else {
                    // 显示频道数量提示
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        Text("发现 \(annotations.count) 个频道")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            // 先更新一次 annotations
            updateAnnotations()
            
            Task { @MainActor in
                isScanning = true
                viewModel.channelManager.startDiscovery()
                // 3秒后停止扫描提示
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                isScanning = false
            }
        }
        .onDisappear {
            viewModel.channelManager.stopDiscovery()
        }
        .navigationTitle("附近频道地图")
        .onReceive(viewModel.didJoinChannel) { channel in
            pushToChat = channel
        }
        .navigationDestination(item: $pushToChat) { channel in
            ChatView(channel: channel, channelManager: viewModel.channelManager)
        }
        .onChange(of: locationProvider.location) { oldValue, newValue in
            if let loc = newValue {
                Task { @MainActor in
                    withAnimation {
                        region.center = loc.coordinate
                    }
                    updateAnnotations()
                }
            }
        }
        .onChange(of: viewModel.channelManager.channels) { oldChannels, newChannels in
            // 延迟状态更新，避免在视图更新期间修改状态
            Task { @MainActor in
                updateAnnotations()
                // 频道列表更新时，停止扫描提示
                if !newChannels.isEmpty {
                    isScanning = false
                }
            }
        }
    }
    
    private func updateAnnotations() {
        // 直接使用 channelManager 的 channels，避免示例频道干扰
        let channels = viewModel.channelManager.channels
        guard !channels.isEmpty else {
            annotations = []
            return
        }
        
        guard let base = locationProvider.location?.coordinate else {
            annotations = channels.enumerated().map { (idx, ch) in
                ChannelAnnotation(channel: ch, title: ch.name, coordinate: jitter(base: region.center, idx: idx))
            }
            return
        }
        
        annotations = channels.enumerated().map { (idx, ch) in
            ChannelAnnotation(channel: ch, title: ch.name, coordinate: jitter(base: base, idx: idx))
        }
    }

    private func jitter(base: CLLocationCoordinate2D, idx: Int) -> CLLocationCoordinate2D {
        let lat = base.latitude + Double((idx % 5) - 2) * 0.001
        let lon = base.longitude + Double(((idx / 5) % 5) - 2) * 0.001
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private struct ChannelAnnotation: Identifiable {
    let id = UUID()
    let channel: Channel
    let title: String
    let coordinate: CLLocationCoordinate2D
}

struct ChannelMapView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ChannelMapView(nickname: "预览") }
    }
}


