import Foundation
import os.log

// 定义通知名称
extension Notification.Name {
    static let startCollectionRequested = Notification.Name("StartCollectionRequested")
    static let stopCollectionRequested = Notification.Name("StopCollectionRequested")
    static let exportDataRequested = Notification.Name("ExportDataRequested")
    static let gestureResultReceived = Notification.Name("GestureResultReceived")
    static let settingsUpdated = Notification.Name("SettingsUpdated")
}

class MessageHandlerService {
    static let shared = MessageHandlerService()
    
    private let logger = Logger(subsystem: "com.wayne.MicroHandGestureCollectorIWatch", category: "MessageHandler")
    private let bleService = BlePeripheralService.shared
    
    private init() {
        setupNotificationObservers()
    }
    
    // 设置通知观察者
    private func setupNotificationObservers() {
        // 观察来自WatchConnectivity的消息
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWatchConnectivityMessage(_:)),
            name: NSNotification.Name("ReceivedWatchMessage"),
            object: nil
        )
        
        // 观察来自BLE的JSON数据
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBleJsonData(_:)),
            name: .didReceiveJsonData,
            object: nil
        )
        
        // 观察来自BLE的手势数据
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBleGesture(_:)),
            name: .didReceiveGesture,
            object: nil
        )
    }
    
    // 处理WatchConnectivity消息
    @objc private func handleWatchConnectivityMessage(_ notification: Notification) {
        if let message = notification.userInfo as? [String: Any] {
            processMessage(message)
        }
    }
    
    // 处理BLE发来的JSON数据
    @objc private func handleBleJsonData(_ notification: Notification) {
        if let jsonData = notification.userInfo as? [String: Any] {
            processMessage(jsonData)
        }
    }
    
    // 处理BLE发来的手势数据
    @objc private func handleBleGesture(_ notification: Notification) {
        if let gesture = notification.userInfo?["gesture"] as? String {
            // 这里可以处理简单手势，例如游戏控制
            logger.info("收到手势: \(gesture)")
            
            // 可以转发通知给需要处理手势的组件
            NotificationCenter.default.post(
                name: .gestureReceived,
                object: nil,
                userInfo: ["gesture": gesture]
            )
        }
    }
    
    // 统一处理消息
    func processMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        // 只打印非传感器数据的消息
        if type != "batch_data" && type != "sensor_data" {
            logger.info("收到消息: \(type)")
        }
        
        switch type {
        case "start_collection":
            handleStartCollection(message)
        case "stop_collection":
            handleStopCollection(message)
        case "request_export":
            handleRequestExport(message)
        case "gesture_result":
            handleGestureResult(message)
        case "update_settings":
            handleUpdateSettings(message)
        default:
            logger.info("未处理的消息类型: \(type)")
        }
    }
    
    // MARK: - 消息处理方法
    
    private func handleStartCollection(_ message: [String: Any]) {
        logger.info("收到开始采集消息 (来自 BLE)")

        if let folderName = message["folder_name"] as? String {
            SensorDataManager.shared.updateFolderNameAndLogger(folderName)
        } else {
            logger.warning("开始采集消息中未找到 folder_name")
        }

        // 通过通知中心广播消息
        NotificationCenter.default.post(
            name: .startCollectionRequested,
            object: nil,
            userInfo: message
        )
    }
    
    private func handleStopCollection(_ message: [String: Any]) {
        logger.info("收到停止采集消息")
        
        // 通过通知中心广播消息
        NotificationCenter.default.post(
            name: .stopCollectionRequested,
            object: nil,
            userInfo: message
        )
    }
    
    private func handleRequestExport(_ message: [String: Any]) {
        logger.info("收到请求导出数据消息")
        
        // 通过通知中心广播消息
        NotificationCenter.default.post(
            name: .exportDataRequested,
            object: nil,
            userInfo: message
        )
    }
    
    private func handleGestureResult(_ message: [String: Any]) {
        if let gesture = message["gesture"] as? String {
            logger.info("收到手势识别结果: \(gesture)")
            
            // 通过通知中心广播消息
            NotificationCenter.default.post(
                name: .gestureResultReceived,
                object: nil,
                userInfo: message
            )
        }
    }
    
    private func handleUpdateSettings(_ message: [String: Any]) {
        logger.info("收到更新设置消息")
        
        // 通过通知中心广播消息
        NotificationCenter.default.post(
            name: .settingsUpdated,
            object: nil,
            userInfo: message
        )
    }
    
    // MARK: - 发送消息方法
    
    // 发送手势结果更新
    func sendGestureResultUpdate(id: String, bodyGesture: String, armGesture: String, fingerGesture: String) {
        let message: [String: Any] = [
            "type": "update_gesture_result",
            "id": id,
            "body_gesture": bodyGesture,
            "arm_gesture": armGesture,
            "finger_gesture": fingerGesture
        ]
        
        logger.info("发送动作更新 - ID: \(id)")
        bleService.sendJSONData(message)
    }
    
    // 发送真实手势更新
    func sendTrueGestureUpdate(id: String, trueGesture: String) {
        let message: [String: Any] = [
            "type": "update_true_gesture",
            "id": id,
            "true_gesture": trueGesture
        ]
        
        logger.info("发送真实手势更新 - ID: \(id), 真实手势: \(trueGesture)")
        bleService.sendJSONData(message)
    }
}

// 添加额外的通知名称
extension Notification.Name {
    static let gestureReceived = Notification.Name("GestureReceived")
} 
