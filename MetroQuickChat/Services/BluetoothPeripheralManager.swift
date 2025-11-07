import Foundation
import CoreBluetooth
import Combine

@MainActor
final class BluetoothPeripheralManager: NSObject, ObservableObject {
    enum PeripheralState: Equatable { case idle, advertising, ready, bluetoothUnavailable }

    @Published private(set) var state: PeripheralState = .idle

    let outgoingRequestSubject = PassthroughSubject<Data, Never>()
    let receivedWriteSubject = PassthroughSubject<Data, Never>()

    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    private let characteristicUUID = CBUUID(string: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")

    private var peripheral: CBPeripheralManager!
    private var messageCharacteristic: CBMutableCharacteristic?
    // 关键修复：跟踪已订阅的 Central 列表
    private var subscribedCentrals: Set<CBCentral> = []

    override init() {
        super.init()
        // 使用主队列初始化，避免 XPC 连接问题
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising(localName: String, hostNickname: String? = nil, hostDeviceId: UUID? = nil) {
        // 如果状态未知，等待状态更新
        if peripheral.state == .unknown {
            print("BluetoothPeripheralManager: 蓝牙状态未知，等待初始化完成...")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // 等待最多3秒状态更新
                for _ in 0..<30 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    if self.peripheral.state != .unknown {
                        if self.peripheral.state == .poweredOn {
                            self.startAdvertising(localName: localName)
                        } else {
                            let stateString: String
                            switch self.peripheral.state {
                            case .unknown: stateString = "未知"
                            case .resetting: stateString = "重置中"
                            case .unsupported: stateString = "不支持"
                            case .unauthorized: stateString = "未授权"
                            case .poweredOff: stateString = "已关闭"
                            case .poweredOn: stateString = "已开启"
                            @unknown default: stateString = "未知状态"
                            }
                            print("BluetoothPeripheralManager: 蓝牙未就绪，当前状态: \(stateString)")
                        }
                        return
                    }
                }
                print("BluetoothPeripheralManager: ⚠️ 等待蓝牙状态超时")
            }
            return
        }
        
        guard peripheral.state == .poweredOn else {
            let stateString: String
            switch peripheral.state {
            case .unknown: stateString = "未知"
            case .resetting: stateString = "重置中"
            case .unsupported: stateString = "不支持"
            case .unauthorized: stateString = "未授权"
            case .poweredOff: stateString = "已关闭"
            case .poweredOn: stateString = "已开启"
            @unknown default: stateString = "未知状态"
            }
            print("BluetoothPeripheralManager: 蓝牙未开启，当前状态: \(stateString)")
            state = .bluetoothUnavailable
            return
        }
        if messageCharacteristic == nil {
            setupService()
        }
        
        // 构建广播名称：如果提供了房主信息，则包含在广播中
        // 格式：频道名|昵称#设备ID（前8位）
        var broadcastName = localName
        if let nickname = hostNickname, let deviceId = hostDeviceId {
            let shortDeviceId = deviceId.uuidString.prefix(8)
            broadcastName = "\(localName)|\(nickname)#\(shortDeviceId)"
        }
        
        let data: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: broadcastName]
        peripheral.startAdvertising(data)
        state = .advertising
    }

    func stopAdvertising() {
        peripheral.stopAdvertising()
        state = .idle
    }

    func notify(_ data: Data) {
        guard let characteristic = messageCharacteristic else {
            NSLog("❌ BluetoothPeripheralManager: 无法发送通知，特征值未设置")
            return
        }
        
        NSLog("📤 BluetoothPeripheralManager: 准备发送通知 - 大小: \(data.count) 字节, 订阅数: \(subscribedCentrals.count)")
        
        // 关键修复：向所有已订阅的 Central 发送通知
        if subscribedCentrals.isEmpty {
            NSLog("⚠️ BluetoothPeripheralManager: 没有订阅的 Central，通知可能无法发送")
            // 仍然尝试发送（可能在订阅确认之前）
            let success = peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
            if !success {
                NSLog("❌ BluetoothPeripheralManager: 通知发送失败（队列满或无订阅者）")
            } else {
                NSLog("⚠️ BluetoothPeripheralManager: 通知已发送（但没有订阅者记录）")
            }
        } else {
            // 向所有已订阅的 Central 发送
            let centralsArray = Array(subscribedCentrals)
            let success = peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: centralsArray)
            if success {
                NSLog("✅ BluetoothPeripheralManager: 通知已发送给 \(subscribedCentrals.count) 个订阅的 Central")
            } else {
                NSLog("⚠️ BluetoothPeripheralManager: 通知发送失败（可能是队列满），但有 \(subscribedCentrals.count) 个订阅者")
            }
        }
    }

    private func setupService() {
        messageCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )

        let service = CBMutableService(type: serviceUUID, primary: true)
        if let characteristic = messageCharacteristic {
            service.characteristics = [characteristic]
        }
        peripheral.add(service)
    }
}

extension BluetoothPeripheralManager: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let stateString: String
        switch peripheral.state {
        case .unknown: stateString = "未知"
        case .resetting: stateString = "重置中"
        case .unsupported: stateString = "不支持"
        case .unauthorized: stateString = "未授权"
        case .poweredOff: stateString = "已关闭"
        case .poweredOn: stateString = "已开启"
        @unknown default: stateString = "未知状态"
        }
        print("BluetoothPeripheralManager: 状态更新 - \(stateString) (rawValue: \(peripheral.state.rawValue))")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch peripheral.state {
            case .poweredOn:
                self.state = .ready
                print("BluetoothPeripheralManager: 蓝牙已就绪")
            case .unauthorized:
                self.state = .bluetoothUnavailable
                print("BluetoothPeripheralManager: ⚠️ 蓝牙权限未授权，请在设置中授予权限")
            case .unsupported:
                self.state = .bluetoothUnavailable
                print("BluetoothPeripheralManager: ⚠️ 设备不支持蓝牙")
            case .poweredOff:
                self.state = .bluetoothUnavailable
                print("BluetoothPeripheralManager: ⚠️ 蓝牙已关闭，请在设置中开启蓝牙")
            case .resetting:
                self.state = .bluetoothUnavailable
                print("BluetoothPeripheralManager: 蓝牙重置中...")
            case .unknown:
                self.state = .bluetoothUnavailable
                print("BluetoothPeripheralManager: 蓝牙状态未知，等待初始化...")
            @unknown default:
                self.state = .bluetoothUnavailable
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                let centralId = request.central.identifier
                let dataSize = value.count
                NSLog("📥 BluetoothPeripheralManager: 收到写入数据 - 来源: \(centralId.uuidString.prefix(8)), 大小: \(dataSize) 字节")
                
                Task { @MainActor [weak self] in
                    self?.receivedWriteSubject.send(value)
                    NSLog("✅ BluetoothPeripheralManager: 数据已转发给 ChannelManager")
                }
            } else {
                NSLog("⚠️ BluetoothPeripheralManager: 收到空写入请求")
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        // 关键修复：记录已订阅的 Central
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.subscribedCentrals.insert(central)
            NSLog("✅ BluetoothPeripheralManager: Central 已订阅通知 - \(central.identifier.uuidString.prefix(8))，当前订阅数: \(self.subscribedCentrals.count)")
            NSLog("✅ BluetoothPeripheralManager: 现在可以向 \(self.subscribedCentrals.count) 个 Central 发送通知了！")
        }
    }
    
    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        // 移除取消订阅的 Central
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.subscribedCentrals.remove(central)
            NSLog("❌ BluetoothPeripheralManager: Central 已取消订阅 - \(central.identifier.uuidString.prefix(8))，当前订阅数: \(self.subscribedCentrals.count)")
        }
    }
}


