import Foundation
import CoreBluetooth
import CoreLocation

@MainActor
final class PermissionsObserver: NSObject, ObservableObject {
    @Published var bluetoothAuthorized: Bool = false
    @Published var locationAuthorized: Bool = false

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private let locationManager = CLLocationManager()
    private var didAttemptBLEPrompt = false

    override init() {
        super.init()
        // 使用主队列初始化，避免 XPC 连接问题
        centralManager = CBCentralManager(delegate: self, queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        updateFlags()
    }

    func requestAll() {
        _ = centralManager // ensure initialized
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        updateFlags()
    }

    private func updateFlags() {
        bluetoothAuthorized = CBManager.authorization == .allowedAlways
        let status = locationManager.authorizationStatus
        locationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }
}

extension PermissionsObserver: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateFlags()
        // If not authorized yet and Bluetooth is available, attempt a brief scan to trigger prompt
        if CBManager.authorization == .notDetermined, central.state == .poweredOn, didAttemptBLEPrompt == false {
            didAttemptBLEPrompt = true
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                central.stopScan()
            }
        }
    }
}

extension PermissionsObserver: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateFlags()
    }
}

extension PermissionsObserver: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // No-op, instantiation may help surface peripheral usage prompt on some systems
    }
}


