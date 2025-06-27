import CoreBluetooth
import UIKit
import os.log

// 添加配对状态枚举
enum PairingState {
    case idle           // 空闲状态
    case advertising    // 广播中，等待连接
    case discoverable   // 可被发现状态
    case pairingRequest // 收到配对请求
    case paired         // 已配对
}

// 添加设备信息结构
struct DeviceInfo: Identifiable, Codable {
    let id: String
    let name: String
    let rssi: Int
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, rssi, timestamp
    }
}

class BlePeripheralService: NSObject, ObservableObject {
    static let shared = BlePeripheralService()
    
    // 使用与Android端相同的UUID
    private let serviceUUID = CBUUID(string: "0000180D-0000-1000-8000-00805F9B34FB")
    private let notifyCharacteristicUUID = CBUUID(string: "00002A37-0000-1000-8000-00805F9B34FB")
    private let writeCharacteristicUUID = CBUUID(string: "00002A38-0000-1000-8000-00805F9B34FB")
    
    private var peripheralManager: CBPeripheralManager!
    private var notifyCharacteristic: CBMutableCharacteristic!
    private var writeCharacteristic: CBMutableCharacteristic!
    private var connectedCentrals: Set<CBCentral> = []
    private var timer: Timer?
    private var dataToSendQueue: [Data] = []
    private var isReadyToSend = true
    
    // 添加配对相关状态
    @Published var pairingState: PairingState = .idle
    @Published var pendingPairingRequest: DeviceInfo?
    @Published var isAdvertising = false
    @Published var isConnected = false
    @Published var currentValue = 0
    @Published var connectedDeviceName: String = ""
    
    private var pairingTimer: Timer?
    private let pairingTimeout: TimeInterval = 30.0 // 配对超时30秒
    
    private let logger = Logger(subsystem: "com.wayne.MicroHandGestureCollectorIWatch", category: "BlePeripheral")
    private let deviceName = UIDevice.current.name // 获取设备名称
    
    override private init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    // 开始可发现模式（不自动连接）
    func startDiscoverableMode() {
        guard peripheralManager.state == .poweredOn else {
            logger.error("蓝牙未开启")
            return
        }
        
        setupService()
        
        // 开始广播，包含设备信息
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "iPhone-\(deviceName)"
        ])
        
        pairingState = .discoverable
        isAdvertising = true
        logger.info("开始可发现模式")
    }
    
    // 停止广播
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        if pairingState != .paired {
            pairingState = .idle
        }
        logger.info("停止广播")
    }
    
    // 主动断开连接
    func disconnect() {
        // 清除所有连接的中心设备
        connectedCentrals.removeAll()
        isConnected = false
        connectedDeviceName = ""
        pairingState = .idle
        stopCounter()
        
        // 注意：CBPeripheralManager没有直接断开连接的方法
        // 连接是由中心设备发起的，断开也需要中心设备或系统处理
        logger.info("断开连接")
        
        // 发送断开通知给连接的设备
        sendJSONData([
            "type": "disconnect_request",
            "message": "iPhone主动断开连接"
        ])
    }
    
    // 接受配对请求
    func acceptPairingRequest() {
        guard let request = pendingPairingRequest else { return }
        
        logger.info("接受来自 \(request.name) 的配对请求")
        
        stopPairingTimer() // 停止配对计时器
        
        // 发送配对接受消息
        sendJSONData([
            "type": "pairing_accepted",
            "device_name": deviceName,
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? ""
        ])
        
        pairingState = .paired
        connectedDeviceName = request.name
        pendingPairingRequest = nil
        
        // 开始计数器
        startCounter()
    }
    
    // 拒绝配对请求
    func rejectPairingRequest() {
        guard let request = pendingPairingRequest else { return }
        
        logger.info("拒绝来自 \(request.name) 的配对请求")
        
        stopPairingTimer() // 停止配对计时器
        
        // 发送配对拒绝消息
        sendJSONData([
            "type": "pairing_rejected",
            "device_name": deviceName,
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? ""
        ])
        
        pendingPairingRequest = nil
        pairingState = .discoverable
    }
    
    private func setupService() {
        // 创建特征
        notifyCharacteristic = CBMutableCharacteristic(
            type: notifyCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: .readable
        )
        
        writeCharacteristic = CBMutableCharacteristic(
            type: writeCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: .writeable
        )
        
        // 创建服务
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [notifyCharacteristic, writeCharacteristic]
        
        // 添加服务
        peripheralManager.add(service)
    }
    
    private func startCounter() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentValue = (self.currentValue + 1) % 1000
            self.notifyValueChanged()
            print("计数器更新：\(self.currentValue)")
        }
        print("计数器已启动")
    }
    
    private func stopCounter() {
        timer?.invalidate()
        timer = nil
        print("计数器已停止")
    }
    
    private func notifyValueChanged() {
        guard !connectedCentrals.isEmpty else {
            print("没有已连接的设备，跳过通知")
            return
        }
        
        let value = String(currentValue).data(using: .utf8)
        print("发送计数器值：\(currentValue) 到 \(connectedCentrals.count) 个设备")
        peripheralManager.updateValue(value!, for: notifyCharacteristic, onSubscribedCentrals: Array(connectedCentrals))
    }
    
    // 新增：发送JSON数据到已连接的中心设备
    func sendJSONData(_ data: [String: Any]) {
        guard !connectedCentrals.isEmpty else {
            print("没有已连接的设备，跳过发送JSON数据")
            return
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            print("通过BLE发送JSON数据：\(data)")
            peripheralManager.updateValue(jsonData, for: notifyCharacteristic, onSubscribedCentrals: Array(connectedCentrals))
        } catch {
            logger.error("JSON序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 新增：发送设置更新到已连接的中心设备
    func sendSettingsUpdate(settings: [String: Any]) {
        guard !connectedCentrals.isEmpty else {
            print("Phone BlePeripheralService: No connected centrals, skipping settings update.")
            return
        }
        
        do {
            // 确保 'type' 字段存在
            var updatedSettings = settings
            if updatedSettings["type"] == nil {
                updatedSettings["type"] = "update_settings"
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: updatedSettings)
            print("Phone BlePeripheralService: Serialized settings JSON (\(jsonData.count) bytes): \(String(data: jsonData, encoding: .utf8) ?? "Invalid UTF8")")
            
            // 发送数据（分块）
            dataToSendQueue.removeAll() // 清空旧队列
            let chunkSize = 20 // MTU 安全块大小
            let totalSize = jsonData.count
            var offset = 0
            
            while offset < totalSize {
                let chunkEnd = min(offset + chunkSize, totalSize)
                let chunk = jsonData.subdata(in: offset..<chunkEnd)
                dataToSendQueue.append(chunk) // 将块添加到队列
                offset += chunkSize
            }
            print("Phone BlePeripheralService: Added \(dataToSendQueue.count) chunks to send queue.")
            
            // 启动发送过程
            sendNextChunk()
            
        } catch {
            print("Phone BlePeripheralService: JSON serialization failed for settings update: \(error.localizedDescription)")
            logger.error("设置更新JSON序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 新增：发送队列中的下一个数据块
    private func sendNextChunk() {
        guard isReadyToSend, !dataToSendQueue.isEmpty else {
            if !isReadyToSend {
                print("Phone BlePeripheralService: sendNextChunk - Not ready to send, waiting for callback.")
            }
            if dataToSendQueue.isEmpty {
                print("Phone BlePeripheralService: sendNextChunk - Queue is empty, all chunks sent.")
            }
            return
        }
        
        // 取出下一个块
        let chunk = dataToSendQueue.removeFirst()
        
        print("Phone BlePeripheralService: Sending chunk (remaining: \(dataToSendQueue.count)), size: \(chunk.count) bytes")
        let success = peripheralManager.updateValue(chunk, for: notifyCharacteristic, onSubscribedCentrals: nil)
        print("Phone BlePeripheralService: updateValue returned: \(success)")
        
        if success {
            // 如果发送成功，立即尝试发送下一个
            print("Phone BlePeripheralService: Chunk sent successfully, trying next chunk immediately.")
            sendNextChunk()
        } else {
            // 如果发送失败（队列满），将块放回队列前面，并等待回调
            print("Phone BlePeripheralService: updateValue returned false, queue might be full. Re-queueing chunk and waiting.")
            dataToSendQueue.insert(chunk, at: 0)
            isReadyToSend = false
        }
    }
}

extension BlePeripheralService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("蓝牙已开启")
            // 不再自动开始可发现模式，需要用户手动开启
        case .poweredOff:
            logger.error("蓝牙已关闭")
            stopAdvertising()
        case .unauthorized:
            logger.error("未授权使用蓝牙")
        case .unsupported:
            logger.error("设备不支持蓝牙")
        case .resetting:
            logger.error("蓝牙重置中")
        case .unknown:
            logger.error("蓝牙状态未知")
        @unknown default:
            logger.error("未知状态")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedCentrals.insert(central)
        isConnected = true
        logger.info("设备已连接")
        
        // 只有在已配对状态下才开始正常工作
        if pairingState != .paired {
            pairingState = .pairingRequest
            startPairingTimer() // 启动配对超时计时器
            logger.info("等待配对确认...")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentrals.remove(central)
        isConnected = !connectedCentrals.isEmpty
        
        if !isConnected {
            pairingState = .idle
            connectedDeviceName = ""
            stopCounter()
        }
        
        logger.info("设备已断开")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == writeCharacteristicUUID,
               let value = request.value {
                
                // 尝试解析为JSON格式数据
                if let jsonObject = try? JSONSerialization.jsonObject(with: value, options: []) as? [String: Any] {
                    handlePairingMessage(jsonObject)
                    
                    // 直接发送原始JSON数据通知，不在BLE服务中解析业务数据
                    logger.info("收到JSON格式数据")
                    print("Phone BlePeripheralService: Received JSON data: \(jsonObject)")
                    NotificationCenter.default.post(
                        name: .didReceiveJsonData,
                        object: nil,
                        userInfo: jsonObject
                    )
                }
                // 如果不是JSON格式，尝试解析为简单的手势字符串
                else if let gesture = String(data: value, encoding: .utf8) {
                    logger.info("收到手势数据: \(gesture)")
                    // 发送通知以处理手势
                    NotificationCenter.default.post(
                        name: .didReceiveGesture,
                        object: nil,
                        userInfo: ["gesture": gesture]
                    )
                }
            }
            
            if request.characteristic.uuid == writeCharacteristicUUID {
                peripheral.respond(to: request, withResult: .success)
            }
        }
    }
    
    // 处理配对相关消息
    private func handlePairingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "pairing_request":
            if let deviceName = message["device_name"] as? String,
               let deviceId = message["device_id"] as? String {
                
                let deviceInfo = DeviceInfo(
                    id: deviceId,
                    name: deviceName,
                    rssi: message["rssi"] as? Int ?? -50,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.pendingPairingRequest = deviceInfo
                    self.pairingState = .pairingRequest
                }
                
                logger.info("收到来自 \(deviceName) 的配对请求")
            }
            
        case "disconnect_request":
            DispatchQueue.main.async {
                self.disconnect()
            }
            logger.info("收到断开连接请求")
            
        default:
            break
        }
    }
    
    // MARK: - 配对超时处理
    private func startPairingTimer() {
        stopPairingTimer() // 先停止之前的计时器
        pairingTimer = Timer.scheduledTimer(withTimeInterval: pairingTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePairingTimeout()
            }
        }
    }
    
    private func stopPairingTimer() {
        pairingTimer?.invalidate()
        pairingTimer = nil
    }
    
    private func handlePairingTimeout() {
        logger.warning("配对超时")
        DispatchQueue.main.async {
            self.pairingState = .discoverable
            self.pendingPairingRequest = nil
            
            // 发送超时通知给连接的设备
            self.sendJSONData([
                "type": "pairing_timeout",
                "message": "配对超时"
            ])
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate Flow Control
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("Phone BlePeripheralService: Peripheral manager is ready to send data again.")
        isReadyToSend = true
        sendNextChunk() // 尝试发送队列中的下一个块
    }
}

extension Notification.Name {
    static let didReceiveGesture = Notification.Name("didReceiveGesture")
    static let didReceiveJsonData = Notification.Name("didReceiveJsonData")
} 