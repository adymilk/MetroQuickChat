import Foundation
import CoreBluetooth
import Combine
import UIKit

@MainActor
final class BluetoothCentralManager: NSObject, ObservableObject {
    enum CentralState: Equatable {
        case idle, scanning, connecting, connected, disconnected(Error?), bluetoothUnavailable
        static func == (lhs: CentralState, rhs: CentralState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.scanning, .scanning), (.connecting, .connecting), (.connected, .connected), (.bluetoothUnavailable, .bluetoothUnavailable):
                return true
            case (.disconnected(let le), .disconnected(let re)):
                let ls = le.map { ($0 as NSError).domain + "|" + String(($0 as NSError).code) } ?? "nil"
                let rs = re.map { ($0 as NSError).domain + "|" + String(($0 as NSError).code) } ?? "nil"
                return ls == rs
            default:
                return false
            }
        }
    }

    @Published private(set) var state: CentralState = .idle
    @Published private(set) var connectedPeripheralName: String? = nil

    let incomingDataSubject = PassthroughSubject<Data, Never>()
    let connectionEventSubject = PassthroughSubject<CentralState, Never>()
    let discoveredSubject = PassthroughSubject<(UUID, String, String?, UUID?), Never>() // (identifier, channelName, hostNickname, hostDeviceId)

    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    private let characteristicUUID = CBUUID(string: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")

    private var central: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var idToPeripheral: [UUID: CBPeripheral] = [:]
    private var messageCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        // 使用主队列初始化，避免 XPC 连接问题
        self.central = CBCentralManager(delegate: self, queue: .main)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if case .disconnected = self.state { self.startScanning() }
        }
    }

    private var isScanningInProgress = false
    private var lastScanAttempt: Date?
    
    func startScanning() {
        // 如果正在扫描，直接返回（不打印日志，避免干扰）
        if isScanningInProgress, case .scanning = state {
            // 静默忽略，不打印日志（避免日志过多）
            return
        }
        
        // 防止重复扫描（防抖）
        let now = Date()
        if let lastAttempt = lastScanAttempt, now.timeIntervalSince(lastAttempt) < 1.0 {
            // 静默忽略频繁请求
            return
        }
        lastScanAttempt = now
        
        // 等待蓝牙状态更新完成
        guard central.state != .unknown else {
            print("BluetoothCentralManager: 蓝牙状态未知，等待初始化完成...")
            // 延迟重试
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                if self.central.state != .unknown {
                    self.startScanning()
                }
            }
            return
        }
        
        guard central.state == .poweredOn else {
            let stateString: String
            switch central.state {
            case .unknown: stateString = "未知"
            case .resetting: stateString = "重置中"
            case .unsupported: stateString = "不支持"
            case .unauthorized: stateString = "未授权"
            case .poweredOff: stateString = "已关闭"
            case .poweredOn: stateString = "已开启"
            @unknown default: stateString = "未知状态"
            }
            print("BluetoothCentralManager: 蓝牙未开启，当前状态: \(stateString) (rawValue: \(central.state.rawValue))")
            state = .bluetoothUnavailable
            isScanningInProgress = false
            return
        }
        
        print("BluetoothCentralManager: 开始扫描，Service UUID: \(serviceUUID)")
        isScanningInProgress = true
        state = .scanning
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        isScanningInProgress = false
        if case .scanning = state { state = .idle }
    }

    func connect(to identifier: UUID) {
        guard let peripheral = idToPeripheral[identifier] else { return }
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = discoveredPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func send(_ data: Data) {
        guard let peripheral = discoveredPeripheral, let characteristic = messageCharacteristic as? CBMutableCharacteristic ?? messageCharacteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

extension BluetoothCentralManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateString: String
        switch central.state {
        case .unknown: stateString = "未知"
        case .resetting: stateString = "重置中"
        case .unsupported: stateString = "不支持"
        case .unauthorized: stateString = "未授权"
        case .poweredOff: stateString = "已关闭"
        case .poweredOn: stateString = "已开启"
        @unknown default: stateString = "未知状态"
        }
        print("BluetoothCentralManager: 状态更新 - \(stateString) (rawValue: \(central.state.rawValue))")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch central.state {
            case .poweredOn:
                self.state = .idle
                print("BluetoothCentralManager: 蓝牙已就绪")
            case .unauthorized:
                self.state = .bluetoothUnavailable
                print("BluetoothCentralManager: ⚠️ 蓝牙权限未授权，请在设置中授予权限")
            case .unsupported:
                self.state = .bluetoothUnavailable
                print("BluetoothCentralManager: ⚠️ 设备不支持蓝牙")
            case .poweredOff:
                self.state = .bluetoothUnavailable
                print("BluetoothCentralManager: ⚠️ 蓝牙已关闭，请在设置中开启蓝牙")
            case .resetting:
                self.state = .bluetoothUnavailable
                print("BluetoothCentralManager: 蓝牙重置中...")
            case .unknown:
                self.state = .bluetoothUnavailable
                print("BluetoothCentralManager: 蓝牙状态未知，等待初始化...")
            @unknown default:
                self.state = .bluetoothUnavailable
            }
            self.connectionEventSubject.send(self.state)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("BluetoothCentralManager: 发现设备 - \(peripheral.identifier), RSSI: \(RSSI)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.idToPeripheral[peripheral.identifier] = peripheral
            let rawName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? (peripheral.name ?? "未知频道")
            
            // 解析广播名称：格式为 "频道名|昵称#设备ID" 或 "频道名"
            var channelName = rawName
            var hostNickname: String? = nil
            var hostDeviceId: UUID? = nil
            
            if let pipeIndex = rawName.firstIndex(of: "|") {
                // 包含房主信息
                channelName = String(rawName[..<pipeIndex])
                let hostInfo = String(rawName[rawName.index(after: pipeIndex)...])
                
                // 解析昵称和设备ID：格式 "昵称#设备ID前8位"
                if let hashIndex = hostInfo.firstIndex(of: "#") {
                    hostNickname = String(hostInfo[..<hashIndex])
                    let deviceIdString = String(hostInfo[hostInfo.index(after: hashIndex)...])
                    // 尝试从8位短码恢复完整UUID（如果不能恢复，就使用短码创建UUID）
                    // 注意：BLE广播的限制，我们只能存储8位，所以用这个作为设备标识的一部分
                    // 实际使用中，我们需要完整的UUID，但可以通过其他方式获取
                    // 这里先解析出8位，后续可以从连接后的消息中获取完整信息
                    if let uuid = UUID(uuidString: deviceIdString) {
                        hostDeviceId = uuid
                    } else {
                        // 如果不能直接解析为UUID，创建一个基于短码的UUID
                        // 但这只是为了存储，真正的设备ID应该从后续通信中获取
                        print("BluetoothCentralManager: 设备ID短码: \(deviceIdString)")
                    }
                } else {
                    hostNickname = hostInfo
                }
            }
            
            print("BluetoothCentralManager: 频道名称 - \(channelName), 房主: \(hostNickname ?? "未知"), 设备ID: \(hostDeviceId?.uuidString.prefix(8) ?? "未知")")
            self.discoveredSubject.send((peripheral.identifier, channelName, hostNickname, hostDeviceId))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectedPeripheralName = peripheral.name
            self.state = .connected
            peripheral.delegate = self
            peripheral.discoverServices([self.serviceUUID])
            self.connectionEventSubject.send(.connected)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.state = .disconnected(error)
            self.connectionEventSubject.send(.disconnected(error))
            // Attempt reconnect after short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.startScanning()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.state = .disconnected(error)
            self.connectionEventSubject.send(.disconnected(error))
            // Auto-reconnect
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.startScanning()
        }
    }
}

extension BluetoothCentralManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for service in services where service.uuid == self.serviceUUID {
                peripheral.discoverCharacteristics([self.characteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        guard let characteristics = service.characteristics else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for characteristic in characteristics where characteristic.uuid == self.characteristicUUID {
                self.messageCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        guard let value = characteristic.value else { return }
        Task { @MainActor [weak self] in
            self?.incomingDataSubject.send(value)
        }
    }
}


