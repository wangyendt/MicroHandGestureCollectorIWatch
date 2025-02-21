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
}

extension BleCentralService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("蓝牙已开启")
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
        
        if characteristic.uuid == notifyCharacteristicUUID,
           let data = characteristic.value,
           let valueString = String(data: data, encoding: .utf8),
           let value = Int(valueString) {
            DispatchQueue.main.async {
                self.currentValue = value
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