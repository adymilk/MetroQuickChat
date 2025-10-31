import SwiftUI
import CoreBluetooth
import CoreLocation

@MainActor
struct OnboardingView: View {
    var onFinished: (() -> Void)? = nil
    @StateObject private var permissions = PermissionsObserver()
    @State private var proceed = false

    var body: some View {
        VStack(spacing: 24) {
            Text("地铁快打")
                .font(.largeTitle.bold())
            Text("基于蓝牙的本地频道聊天。")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(title: "蓝牙", granted: permissions.bluetoothAuthorized)
                permissionRow(title: "定位", granted: permissions.locationAuthorized)
                permissionRow(title: "通知", granted: NotificationService.shared.isAuthorized)
                // Debug statuses for troubleshooting on devices
                Text(debugStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .task {
                // 请求通知权限
                await NotificationService.shared.requestAuthorization()
            }
            if !(permissions.bluetoothAuthorized && permissions.locationAuthorized) {
                Text("请允许蓝牙和定位权限以继续").foregroundStyle(.red).font(.caption)
            }
            Button(action: { proceed = true; UserDefaults.standard.set(true, forKey: "onboardingDone"); onFinished?() }) {
                Text("开始使用")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(permissions.bluetoothAuthorized && permissions.locationAuthorized))
            .padding(.top, 12)

            if !(permissions.bluetoothAuthorized && permissions.locationAuthorized) {
                Button("前往设置开启权限") { openSettings() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear { permissions.requestAll() }
        .navigationDestination(isPresented: $proceed) {
            HomeView()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(granted ? .green : .red)
            Text(title).font(.headline)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? .gray : .red)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var debugStatusText: String {
        let bleAuth: String
        switch CBManager.authorization {
        case .allowedAlways: bleAuth = "BLE: allowedAlways"
        case .restricted: bleAuth = "BLE: restricted"
        case .denied: bleAuth = "BLE: denied"
        case .notDetermined: bleAuth = "BLE: notDetermined"
        @unknown default: bleAuth = "BLE: unknown"
        }

        let lm = CLLocationManager()
        let locAuth: String
        switch lm.authorizationStatus {
        case .authorizedAlways: locAuth = "LOC: always"
        case .authorizedWhenInUse: locAuth = "LOC: whenInUse"
        case .denied: locAuth = "LOC: denied"
        case .restricted: locAuth = "LOC: restricted"
        case .notDetermined: locAuth = "LOC: notDetermined"
        @unknown default: locAuth = "LOC: unknown"
        }
        return bleAuth + " | " + locAuth
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // permissionRow remains
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { OnboardingView() }
            .preferredColorScheme(.dark)
        NavigationStack { OnboardingView() }
            .preferredColorScheme(.light)
            .previewDevice("iPad (10th generation)")
    }
}


