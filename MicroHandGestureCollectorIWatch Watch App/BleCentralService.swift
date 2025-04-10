import Foundation
import CoreBluetooth
import os.log

class BleCentralService: NSObject, ObservableObject {
    static let shared = BleCentralService()
    
    // 使用与Android端相同的UUID
    private let serviceUUID = CBUUID(string: "0000180D-0000-1000-8000-00805F9B34FB")
    private let notifyCharacteristicUUID = CBUUID(string: "00002A37-0000-1000-8000-00805F9B34FB")
    private let writeCharacteristicUUID = CBUUID(string: "00002A38-0000-1000-8000-00805F9B34FB")
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var currentValue: Int = 0
    @Published var lastError: String?
    
    // 添加自动重连标志
    private var shouldAutoReconnect = true
    
    private let logger = Logger(subsystem: "com.wayne.MicroHandGestureCollectorIWatch", category: "BleCentral")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "蓝牙未开启"
            return
        }
        
        shouldAutoReconnect = true
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        logger.info("开始扫描设备")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        logger.info("停止扫描设备")
    }
    
    func disconnect() {
        shouldAutoReconnect = false  // 用户主动断开时，禁用自动重连
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
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
}

extension BleCentralService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("蓝牙已开启")
            // 自动开始扫描
            startScanning()
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
        logger.info("发现设备: \(peripheral.name ?? "未知设备")")
        
        // 停止扫描
        stopScanning()
        
        // 连接设备
        self.peripheral = peripheral
        central.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("已连接到设备: \(peripheral.name ?? "未知设备")")
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
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
        
        // 只有在shouldAutoReconnect为true时才自动重新扫描
        if shouldAutoReconnect {
            startScanning()
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
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            logger.error("读取特性值出错: \(error!.localizedDescription)")
            return
        }
        
        if characteristic.uuid == notifyCharacteristicUUID, let data = characteristic.value {
            print("Watch App BleCentralService: Received raw data (size: \(data.count) bytes): \(data as NSData)")
            if let stringData = String(data: data, encoding: .utf8) {
                print("Watch App BleCentralService: Raw data as UTF8 string: \(stringData)")
            }

            // 尝试直接解析为 JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                print("Watch App BleCentralService: Successfully parsed as JSON: \(jsonObject)")

                // 检查是否是手机开始时间戳消息
                if let type = jsonObject["type"] as? String, type == "phone_start_timestamp",
                   let timestamp = jsonObject["timestamp"] as? TimeInterval {
                    print("Watch App BleCentralService: Received phone_start_timestamp: \(String(format: "%.6f", timestamp))")
                    // 发送通知
                    print("Watch App BleCentralService: Posting .phoneStartTimestampReceived notification.")
                    NotificationCenter.default.post(
                        name: .phoneStartTimestampReceived,
                        object: nil,
                        userInfo: ["timestamp": timestamp]
                    )
                // 检查是否是设置更新消息
                } else if let type = jsonObject["type"] as? String, type == "update_settings" {
                    self.logger.info("Watch App BleCentralService: Received settings update.")
                    updateUserDefaults(from: jsonObject)
                } else {
                    // 其他 JSON 消息
                    print("Watch App BleCentralService: Forwarding other JSON to MessageHandler/WCSession.")
                    WatchConnectivityManager.shared.processMessage(jsonObject)
                    print("Watch App BleCentralService: Posting .didReceiveBleJsonData notification.")
                    NotificationCenter.default.post(
                        name: .didReceiveBleJsonData,
                        object: nil,
                        userInfo: jsonObject
                    )
                }
            // 如果 JSON 解析失败，尝试解析为 Int (计数器值)
            } else if let valueString = String(data: data, encoding: .utf8), let value = Int(valueString) {
                print("Watch App BleCentralService: Received counter value: \(value).")
                DispatchQueue.main.async {
                    self.currentValue = value
                }
            // 如果两者都失败
            } else {
                print("Watch App BleCentralService: Failed to parse received data as JSON or Int.")
            }
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