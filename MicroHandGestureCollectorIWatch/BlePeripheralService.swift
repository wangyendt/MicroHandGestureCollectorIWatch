import CoreBluetooth
import os.log

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
    
    @Published var isAdvertising = false
    @Published var isConnected = false
    @Published var currentValue = 0
    
    private let logger = Logger(subsystem: "com.wayne.MicroHandGestureCollectorIWatch", category: "BlePeripheral")
    
    override private init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            logger.error("蓝牙未开启")
            return
        }
        
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
        
        // 开始广播
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "手势游戏"
        ])
        
        isAdvertising = true
        logger.info("开始广播")
        
        // 启动计数器
        startCounter()
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        isConnected = false
        connectedCentrals.removeAll()
        stopCounter()
        logger.info("停止广播")
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
}

extension BlePeripheralService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("蓝牙已开启")
            startAdvertising()  // 自动开始广播
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
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentrals.remove(central)
        isConnected = !connectedCentrals.isEmpty
        logger.info("设备已断开")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == writeCharacteristicUUID,
               let value = request.value {
                
                // 尝试解析为JSON格式数据
                if let jsonObject = try? JSONSerialization.jsonObject(with: value, options: []) as? [String: Any] {
                    // 直接发送原始JSON数据通知，不在BLE服务中解析业务数据
                    logger.info("收到JSON格式数据")
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
}

extension Notification.Name {
    static let didReceiveGesture = Notification.Name("didReceiveGesture")
    static let didReceiveJsonData = Notification.Name("didReceiveJsonData")
} 