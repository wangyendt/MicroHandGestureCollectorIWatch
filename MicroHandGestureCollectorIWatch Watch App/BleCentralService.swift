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
            // 尝试解析为普通数字（计数器值）
            if let valueString = String(data: data, encoding: .utf8), let value = Int(valueString) {
                DispatchQueue.main.async {
                    self.currentValue = value
                }
            } 
            // 尝试解析为JSON数据
            else if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                logger.info("收到JSON格式数据")
                
                // 直接处理start_collection和stop_collection消息（添加）
                if let type = jsonObject["type"] as? String {
                    logger.info("收到BLE消息类型: \(type)")
                    
                    // 针对特殊消息类型直接发送通知
                    if type == "start_collection" || type == "stop_collection" || type == "request_export" {
                        let notificationName: Notification.Name
                        switch type {
                        case "start_collection":
                            notificationName = NSNotification.Name("StartCollectionRequested")
                            logger.info("收到开始采集请求，直接发送通知")
                        case "stop_collection":
                            notificationName = NSNotification.Name("StopCollectionRequested")
                            logger.info("收到停止采集请求，直接发送通知")
                        case "request_export":
                            notificationName = NSNotification.Name("ExportDataRequested")
                            logger.info("收到导出数据请求，直接发送通知")
                        default:
                            notificationName = NSNotification.Name("UnknownRequestType")
                        }
                        
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: notificationName,
                                object: nil, 
                                userInfo: jsonObject
                            )
                        }
                    }
                }
                
                // 发送通知，以便应用其他部分可以处理这些消息
                DispatchQueue.main.async {
                    // 检查是否是设置更新消息
                    if let type = jsonObject["type"] as? String, type == "update_settings" {
                        self.logger.info("收到手表设置更新")
                        NotificationCenter.default.post(
                            name: .didReceiveSettingsUpdate, // 使用新的通知名称
                            object: nil,
                            userInfo: jsonObject
                        )
                    } else {
                        // 其他 JSON 消息继续走之前的逻辑
                        // 发送通知给 MessageHandlerService (通过 WatchConnectivityManager 间接触发)
                        WatchConnectivityManager.shared.processMessage(jsonObject)
                        
                        // 同时仍然发送通知，保持向后兼容 (可能可以移除，取决于 MessageHandler 是否完全依赖 WCSession 触发)
                        NotificationCenter.default.post(
                            name: .didReceiveBleJsonData,
                            object: nil,
                            userInfo: jsonObject
                        )
                    }
                }
            }
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
} 