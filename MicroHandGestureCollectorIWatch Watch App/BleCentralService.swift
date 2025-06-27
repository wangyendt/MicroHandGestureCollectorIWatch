import Foundation
import CoreBluetooth
import WatchKit
import os.log

// 添加配对状态枚举
enum WatchPairingState {
    case idle           // 空闲状态
    case scanning       // 扫描中
    case deviceFound    // 发现设备
    case pairingRequest // 发送配对请求
    case waitingResponse // 等待配对响应
    case paired         // 已配对
}

// 添加发现的设备信息
struct DiscoveredDevice: Identifiable {
    let id: String
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let timestamp: Date
}

class BleCentralService: NSObject, ObservableObject {
    static let shared = BleCentralService()
    
    // 使用与Android端相同的UUID
    private let serviceUUID = CBUUID(string: "0000180D-0000-1000-8000-00805F9B34FB")
    private let notifyCharacteristicUUID = CBUUID(string: "00002A37-0000-1000-8000-00805F9B34FB")
    private let writeCharacteristicUUID = CBUUID(string: "00002A38-0000-1000-8000-00805F9B34FB")
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    @Published var pairingState: WatchPairingState = .idle
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var currentValue: Int = 0
    @Published var lastError: String?
    @Published var connectedDeviceName: String = ""
    @Published var pairingMessage: String = ""
    
    // 添加自动重连标志
    private var shouldAutoReconnect = false // 改为默认false，需要手动配对
    private var selectedDeviceId: String?
    private var pairingTimer: Timer?
    private let pairingTimeout: TimeInterval = 30.0 // 配对超时30秒
    
    // 添加数据缓冲区用于处理分块数据
    private var incomingDataBuffer = Data()
    
    private let logger = Logger(subsystem: "com.wayne.MicroHandGestureCollectorIWatch", category: "BleCentral")
    private let deviceName = WKInterfaceDevice.current().name // 获取手表设备名称
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // 开始扫描可用设备
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "蓝牙未开启"
            return
        }
        
        // 清空之前发现的设备列表
        discoveredDevices.removeAll()
        pairingState = .scanning
        isScanning = true
        
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        logger.info("开始扫描设备")
        
        // 设置扫描超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.isScanning {
                self.stopScanning()
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if discoveredDevices.isEmpty {
            pairingState = .idle
        } else {
            pairingState = .deviceFound
        }
        logger.info("停止扫描设备")
    }
    
    // 向指定设备发送配对请求
    func sendPairingRequest(to device: DiscoveredDevice) {
        selectedDeviceId = device.id
        pairingState = .pairingRequest
        pairingMessage = "正在连接到 \(device.name)..."
        
        // 启动配对超时计时器
        startPairingTimer()
        
        // 连接设备
        centralManager.connect(device.peripheral, options: nil)
        logger.info("向 \(device.name) 发送配对请求")
    }
    
    // 主动断开连接
    func disconnect() {
        shouldAutoReconnect = false
        selectedDeviceId = nil
        stopPairingTimer() // 停止配对计时器
        
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        pairingState = .idle
        connectedDeviceName = ""
        pairingMessage = ""
        logger.info("主动断开连接")
    }
    
    // 重新扫描
    func refreshDevices() {
        if isConnected {
            disconnect()
        }
        discoveredDevices.removeAll()
        startScanning()
    }
    
    func sendGestureData(_ gesture: String) {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic,
              let data = gesture.data(using: .utf8) else {
            lastError = "无法发送手势数据"
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        logger.info("发送手势数据: \(gesture)")
    }
    
    func sendGestureResult(resultDict: [String: Any]) {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else {
            lastError = "无法发送手势结果"
            return
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
            peripheral.writeValue(jsonData, for: characteristic, type: .withResponse)
            
            // 记录简单日志，不解析业务数据
            if let type = resultDict["type"] as? String {
                logger.info("通过BLE发送\(type)数据")
            } else {
                logger.info("通过BLE发送JSON数据")
            }
        } catch {
            lastError = "数据序列化失败: \(error.localizedDescription)"
            logger.error("数据序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 添加发送控制指令的方法
    func sendControlMessage(type: String) {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else {
            lastError = "无法发送控制指令"
            return
        }
        
        let messageDict: [String: Any] = [
            "type": type,
            "trigger_collection": true // 与之前WCSession保持一致
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            peripheral.writeValue(jsonData, for: characteristic, type: .withResponse)
            logger.info("通过BLE发送控制指令: \(type)")
        } catch {
            lastError = "控制指令序列化失败: \(error.localizedDescription)"
            logger.error("控制指令序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 添加发送设置更新的方法
    func sendSettingsUpdate(settings: [String: Any]) {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else {
            lastError = "无法发送设置更新"
            return
        }
        
        do {
            // 确保 'type' 字段存在
            var updatedSettings = settings
            if updatedSettings["type"] == nil {
                updatedSettings["type"] = "update_settings"
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: updatedSettings, options: [])
            peripheral.writeValue(jsonData, for: characteristic, type: .withResponse)
            logger.info("通过BLE发送设置更新")
        } catch {
            lastError = "设置更新序列化失败: \(error.localizedDescription)"
            logger.error("设置更新序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 发送配对请求消息
    private func sendPairingRequestMessage() {
        let message: [String: Any] = [
            "type": "pairing_request",
            "device_name": deviceName,
            "device_id": WKInterfaceDevice.current().identifierForVendor?.uuidString ?? "",
            "rssi": -50
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
            peripheral?.writeValue(jsonData, for: writeCharacteristic!, type: .withResponse)
            logger.info("发送配对请求消息")
            
            pairingState = .waitingResponse
            pairingMessage = "等待配对响应..."
            
        } catch {
            lastError = "配对请求序列化失败: \(error.localizedDescription)"
            logger.error("配对请求序列化失败: \(error.localizedDescription)")
        }
    }
    
    // 处理配对响应
    private func handlePairingResponse(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "pairing_accepted":
            stopPairingTimer() // 停止配对计时器
            if let deviceName = message["device_name"] as? String {
                DispatchQueue.main.async {
                    self.pairingState = .paired
                    self.connectedDeviceName = deviceName
                    self.pairingMessage = "配对成功"
                    self.shouldAutoReconnect = true
                }
                logger.info("配对被接受，来自: \(deviceName)")
            }
            
        case "pairing_rejected":
            stopPairingTimer() // 停止配对计时器
            if let deviceName = message["device_name"] as? String {
                DispatchQueue.main.async {
                    self.pairingState = .idle
                    self.pairingMessage = "配对被拒绝"
                    self.disconnect()
                }
                logger.info("配对被拒绝，来自: \(deviceName)")
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
    
    // 启动配对计时器
    private func startPairingTimer() {
        stopPairingTimer() // 先停止之前的计时器
        pairingTimer = Timer.scheduledTimer(withTimeInterval: pairingTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePairingTimeout()
            }
        }
    }
    
    // 停止配对计时器
    private func stopPairingTimer() {
        pairingTimer?.invalidate()
        pairingTimer = nil
    }
    
    // 处理配对超时
    private func handlePairingTimeout() {
        logger.warning("配对超时")
        DispatchQueue.main.async {
            self.pairingState = .idle
            self.pairingMessage = "配对超时，请重试"
            self.lastError = "配对超时"
            
            // 断开连接
            if let peripheral = self.peripheral {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
}

extension BleCentralService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("蓝牙已开启")
            // 不再自动开始扫描，需要用户手动开启
        case .poweredOff:
            lastError = "蓝牙已关闭"
            isConnected = false
        case .unauthorized:
            lastError = "未授权使用蓝牙"
        case .unsupported:
            lastError = "设备不支持蓝牙"
        case .resetting:
            lastError = "蓝牙重置中"
        case .unknown:
            lastError = "蓝牙状态未知"
        @unknown default:
            lastError = "未知状态"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "未知设备"
        logger.info("发现设备: \(deviceName)")
        
        // 添加到发现的设备列表中（不自动连接）
        let device = DiscoveredDevice(
            id: peripheral.identifier.uuidString,
            peripheral: peripheral,
            name: deviceName,
            rssi: RSSI.intValue,
            timestamp: Date()
        )
        
        // 检查是否已经存在（避免重复）
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                self.discoveredDevices.append(device)
                self.pairingState = .deviceFound
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("已连接到设备: \(peripheral.name ?? "未知设备")")
        isConnected = true
        self.peripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        
        DispatchQueue.main.async {
            self.pairingMessage = "已连接，正在初始化..."
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("连接失败: \(error?.localizedDescription ?? "未知错误")")
        lastError = "连接失败"
        isConnected = false
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("设备已断开连接")
        isConnected = false
        self.peripheral = nil
        self.writeCharacteristic = nil
        
        DispatchQueue.main.async {
            if self.pairingState == .paired {
                self.pairingMessage = "连接已断开"
            }
            self.pairingState = .idle
            self.connectedDeviceName = ""
        }
        
        // 只有在shouldAutoReconnect为true时才自动重新扫描
        if shouldAutoReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.startScanning()
            }
        }
    }
}

extension BleCentralService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("发现服务出错: \(error!.localizedDescription)")
            return
        }
        
        for service in peripheral.services ?? [] {
            if service.uuid == serviceUUID {
                logger.info("发现目标服务")
                peripheral.discoverCharacteristics([notifyCharacteristicUUID, writeCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("发现特性出错: \(error!.localizedDescription)")
            return
        }
        
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == notifyCharacteristicUUID {
                logger.info("发现通知特性")
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == writeCharacteristicUUID {
                logger.info("发现写入特性")
                writeCharacteristic = characteristic
                
                // 特征发现完成后，发送配对请求
                if pairingState == .pairingRequest {
                    sendPairingRequestMessage()
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            logger.error("读取特性值出错: \(error!.localizedDescription)")
            // 如果读取出错，清空缓冲区
            incomingDataBuffer.removeAll()
            return
        }
        
        if characteristic.uuid == notifyCharacteristicUUID, let data = characteristic.value {
            print("Watch App BleCentralService: Received raw data chunk (size: \(data.count) bytes): \(data as NSData)")
            
            // 1. 首先尝试将 *当前数据块* 解析为 Int (计数器)
            if let valueString = String(data: data, encoding: .utf8), let value = Int(valueString) {
                print("Watch App BleCentralService: Parsed chunk directly as counter value: \(value).")
                DispatchQueue.main.async {
                    self.currentValue = value
                }
                // 计数器值处理完毕，不需要放入 JSON 缓冲区，直接返回
                // 并且，如果收到明确的计数器值，可能意味着之前的 JSON 消息（如果有的话）已经结束或被中断，
                // 清理一下缓冲区可能是安全的，以防万一。
                if !incomingDataBuffer.isEmpty {
                    print("Watch App BleCentralService: Received counter value, clearing potentially incomplete JSON buffer.")
                    incomingDataBuffer.removeAll()
                }
                return
            }
            
            // 2. 如果不是 Int，则假定为 JSON 数据块，追加到缓冲区
            incomingDataBuffer.append(data)
            print("Watch App BleCentralService: Appended chunk to buffer. Current buffer size: \(incomingDataBuffer.count) bytes")

            // 3. 尝试将 *整个缓冲区* 解析为 JSON
            do {
                // 使用 .allowFragments 可能有助于处理某些边缘情况，但标准的 JSON 对象应该以 { 开头
                guard incomingDataBuffer.first == UInt8(ascii: "{") else {
                    print("Watch App BleCentralService: Buffer does not start with '{', likely not a valid JSON object yet or corrupted. Buffer content: \(String(data: incomingDataBuffer, encoding: .utf8) ?? "invalid utf8")")
                    // 如果缓冲区开头不是 {，可能不是有效的 JSON，或者包含了之前的非 JSON 数据（如部分计数器）
                    // 考虑是否需要清空缓冲区，或者更智能地找到 { 的位置？
                    // 暂时不清空，等待更多数据看是否能形成有效JSON
                    return
                }
                
                let jsonObject = try JSONSerialization.jsonObject(with: incomingDataBuffer, options: []) as? [String: Any]
                print("Watch App BleCentralService: Successfully parsed buffer as JSON: \(jsonObject ?? [:])")

                // 解析成功，处理 JSON 对象
                if let json = jsonObject {
                    handleParsedJson(json)
                }
                
                // JSON 解析和处理成功后，清空缓冲区
                incomingDataBuffer.removeAll()
                print("Watch App BleCentralService: Cleared buffer after successful JSON processing.")

            } catch let jsonError as NSError {
                // 如果 JSON 解析失败，检查是否是因为数据不完整
                if jsonError.domain == NSCocoaErrorDomain && jsonError.code == 3840 {
                    // 错误码 3840 表示 JSON 数据不完整或损坏，可能是分块传输导致
                    print("Watch App BleCentralService: JSON parsing failed (likely incomplete data), waiting for more data. Error: \(jsonError.localizedDescription)")
                    // 不清空缓冲区，等待下一个数据块
                } else {
                    // 其他 JSON 解析错误，可能是缓冲区数据损坏
                    print("Watch App BleCentralService: JSON parsing failed with unexpected error. Error: \(jsonError.localizedDescription). Clearing buffer.")
                    incomingDataBuffer.removeAll()
                }
            }
        }
    }
    
    // 新增：处理解析后的 JSON 对象
    private func handleParsedJson(_ json: [String: Any]) {
        // 检查是否是手机开始时间戳消息
        if let type = json["type"] as? String, type == "phone_start_timestamp",
           let timestamp = json["timestamp"] as? TimeInterval {
            print("Watch App BleCentralService: Received phone_start_timestamp: \(String(format: "%.6f", timestamp))")
            // 发送通知
            print("Watch App BleCentralService: Posting .phoneStartTimestampReceived notification.")
            NotificationCenter.default.post(
                name: .phoneStartTimestampReceived,
                object: nil,
                userInfo: ["timestamp": timestamp]
            )
        // 检查是否是设置更新消息
        } else if let type = json["type"] as? String, type == "update_settings" {
            self.logger.info("Watch App BleCentralService: Received settings update via buffer.")
            updateUserDefaults(from: json)
        } else {
            // 检查是否是配对相关消息
            if let type = json["type"] as? String,
               ["pairing_accepted", "pairing_rejected", "disconnect_request"].contains(type) {
                handlePairingResponse(json)
            }
            
            // 其他 JSON 消息
            print("Watch App BleCentralService: Forwarding other JSON from buffer to MessageHandler/WCSession.")
            WatchConnectivityManager.shared.processMessage(json)
            print("Watch App BleCentralService: Posting .didReceiveBleJsonData notification from buffer.")
            NotificationCenter.default.post(
                name: .didReceiveBleJsonData,
                object: nil,
                userInfo: json
            )
        }
    }
    
    // 新增：直接更新 UserDefaults 的辅助函数
    private func updateUserDefaults(from settings: [String: Any]) {
        print("Watch App BleCentralService: updateUserDefaults called with: \(settings)")
        DispatchQueue.main.async {
            UserDefaults.standard.set(settings["feedbackType"] as? String ?? "gesture", forKey: "feedbackType")
            UserDefaults.standard.set(settings["peakThreshold"] as? Double ?? 0.5, forKey: "peakThreshold")
            UserDefaults.standard.set(settings["peakWindow"] as? Double ?? 0.6, forKey: "peakWindow")
            UserDefaults.standard.set(settings["saveGestureData"] as? Bool ?? false, forKey: "saveGestureData")
            UserDefaults.standard.set(settings["savePeaks"] as? Bool ?? false, forKey: "savePeaks")
            UserDefaults.standard.set(settings["saveValleys"] as? Bool ?? false, forKey: "saveValleys")
            UserDefaults.standard.set(settings["saveSelectedPeaks"] as? Bool ?? false, forKey: "saveSelectedPeaks")
            UserDefaults.standard.set(settings["saveQuaternions"] as? Bool ?? false, forKey: "saveQuaternions")
            UserDefaults.standard.set(settings["saveResultFile"] as? Bool ?? true, forKey: "saveResultFile")
            UserDefaults.standard.set(settings["enableVisualFeedback"] as? Bool ?? false, forKey: "enableVisualFeedback")
            UserDefaults.standard.set(settings["enableHapticFeedback"] as? Bool ?? false, forKey: "enableHapticFeedback")
            UserDefaults.standard.set(settings["enableVoiceFeedback"] as? Bool ?? false, forKey: "enableVoiceFeedback")
            UserDefaults.standard.set(settings["enableRealtimeData"] as? Bool ?? false, forKey: "enableRealtimeData")
            UserDefaults.standard.synchronize()
            print("Watch App BleCentralService: Finished updating UserDefaults.")

            // 发送通知，告知设置已通过BLE更新
            NotificationCenter.default.post(name: .userSettingsUpdatedViaBLE, object: nil, userInfo: settings)
            print("Watch App BleCentralService: Posted userSettingsUpdatedViaBLE notification.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("写入数据失败: \(error.localizedDescription)")
            lastError = "写入数据失败"
        } else {
            logger.info("写入数据成功")
        }
    }
}

// 添加通知名称
extension Notification.Name {
    static let didReceiveBleJsonData = Notification.Name("didReceiveBleJsonData")
    static let userSettingsUpdatedViaBLE = Notification.Name("userSettingsUpdatedViaBLE")
    static let phoneStartTimestampReceived = Notification.Name("phoneStartTimestampReceived")
} 