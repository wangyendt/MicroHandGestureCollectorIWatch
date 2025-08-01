import Foundation
import Network
import WatchConnectivity
import QuartzCore
import CoreBluetooth

// 添加手势操作日志记录器
class GestureActionLogger {
    private var currentFolderURL: URL?
    private var logFileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    }
    
    func setCurrentFolder(_ url: URL, folderName: String? = nil) {
        currentFolderURL = url
        
        // 如果提供了文件夹名，使用它来命名日志文件，否则使用当前日期时间
        let logFileName = if let name = folderName {
            "\(name).log"
        } else {
            "\(dateFormatter.string(from: Date())).log"
        }
        let logFileURL = url.appendingPathComponent(logFileName)
        print("创建日志文件：\(logFileURL.path)")
        
        // 如果文件不存在，创建文件并写入表头
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            let header = "timestamp,action,id,body,arm,finger\n"
            try? header.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        
        // 关闭现有的文件句柄
        logFileHandle?.closeFile()
        logFileHandle = nil
        
        // 打开新的文件句柄
        do {
            logFileHandle = try FileHandle(forWritingTo: logFileURL)
            logFileHandle?.seekToEndOfFile()
            print("成功打开日志文件")
        } catch {
            print("打开日志文件失败：\(error)")
        }
    }
    
    func closeFile() {
        logFileHandle?.closeFile()
        logFileHandle = nil
        currentFolderURL = nil
    }
    
    private func logAction(action: String, id: String, timestamp: Double, body: String = "", arm: String = "", finger: String = "") {
        guard let fileHandle = logFileHandle else { return }
        
        let logLine = String(format: "%.3f,%@,%@,%@,%@,%@\n", timestamp, action, id, body, arm, finger)
        
        if let data = logLine.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    func logDelete(id: String, timestamp: Double) {
        logAction(action: "D", id: id, timestamp: timestamp)
    }
    
    func logTrueGestureUpdate(id: String, gesture: String, timestamp: Double) {
        logAction(action: "T", id: id, timestamp: timestamp, body: gesture, arm: "", finger: "")
    }
    
    func logGestureState(id: String, timestamp: Double, body: String, arm: String, finger: String) {
        logAction(action: "G", id: id, timestamp: timestamp, body: body, arm: arm, finger: finger)
    }
}

class SensorDataManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SensorDataManager()
    private var connection: NWConnection?
    private let serverPort: UInt16 = 12345 // Mac服务器端口
    
    // 添加IP地址属性
    @Published var serverHost: String {
        didSet {
            // 当IP地址改变时保存到UserDefaults
            UserDefaults.standard.set(serverHost, forKey: "serverHost")
            // 重新建立连接
            setupMacConnection()
        }
    }
    
    @Published var isConnected = false
    @Published var lastMessage = ""
    @Published var lastReceivedData: [String: Double] = [:]
    @Published var lastUpdateTime = Date()
    @Published var gestureResults: [GestureResult] = []
    
    // 添加当前动作状态
    @Published var currentBodyGesture: String = "无"
    @Published var currentArmGesture: String = "无"
    @Published var currentFingerGesture: String = "无"
    
    @Published var currentFolderName: String?
    
    private var dataQueue = DispatchQueue(label: "com.wayne.dataQueue", qos: .userInteractive)
    private var lastSentTime: TimeInterval = 0
    private let minSendInterval: TimeInterval = 0.005  // 最小发送间隔，100Hz
    
    private var timestampHistory: [UInt64] = []
    private let maxHistorySize = 1000 // 记录更多样本用于统计
    private let minHistorySize = 100  // 最小保留样本数
    
    let actionLogger = GestureActionLogger()
    
    private override init() {
        // 从UserDefaults读取保存的IP地址，如果没有则使用默认值
        self.serverHost = UserDefaults.standard.string(forKey: "serverHost") ?? "192.168.1.1"
        super.init()
        
        setupWatchConnectivity()
        setupMacConnection()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    private func setupMacConnection() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(serverHost),
            port: NWEndpoint.Port(integerLiteral: serverPort)
        )
        
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.lastMessage = "已连接到Mac"
            case .failed(let error):
                self?.isConnected = false
                self?.lastMessage = "连接失败: \(error.localizedDescription)"
                self?.reconnect()
            case .waiting(let error):
                self?.isConnected = false
                self?.lastMessage = "等待连接: \(error.localizedDescription)"
            default:
                break
            }
        }
        
        connection?.start(queue: .global())
    }
    
    private func reconnect() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.setupMacConnection()
        }
    }
    
    func sendDataToMac(_ data: Data) {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastSentTime < minSendInterval {
            return
        }
        
        dataQueue.async { [weak self] in
            // 添加调试信息
//            if let dataString = String(data: data, encoding: .utf8) {
//                print("Sending to Mac:", dataString)
//            }
            
            self?.connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.lastMessage = "发送数据失败: \(error.localizedDescription)"
                    }
                }
            })
            self?.lastSentTime = currentTime
        }
    }
    
    // 修改重置状态的方法
    func resetState() {
        DispatchQueue.main.async {
            self.timestampHistory.removeAll()
            self.lastReceivedData.removeAll()
            self.lastUpdateTime = Date()
            self.lastMessage = ""
            self.lastSentTime = 0
            self.gestureResults.removeAll()
            self.currentFolderName = nil
        }
    }
    
    // 添加更新当前动作的方法
    func updateCurrentGestures(body: String? = nil, arm: String? = nil, finger: String? = nil) {
        DispatchQueue.main.async {
            if let bodyGesture = body {
                self.currentBodyGesture = bodyGesture
                print("更新身体动作为: \(bodyGesture)")
            }
            if let armGesture = arm {
                self.currentArmGesture = armGesture
                print("更新手臂动作为: \(armGesture)")
            }
            if let fingerGesture = finger {
                self.currentFingerGesture = fingerGesture
                print("更新手指动作为: \(fingerGesture)")
            }
            print("当前动作状态 - 身体: \(self.currentBodyGesture), 手臂: \(self.currentArmGesture), 手指: \(self.currentFingerGesture)")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Explicitly log activation result
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                print("✅ iPhone WCSession Activated")
                self.lastMessage = "Watch已连接"
            case .inactive:
                print("⚠️ iPhone WCSession Inactive")
                self.lastMessage = "Watch连接非活动"
            case .notActivated:
                print("❌ iPhone WCSession Not Activated")
                self.lastMessage = "Watch连接未激活"
            @unknown default:
                print("❓ iPhone WCSession Unknown State")
                self.lastMessage = "Watch连接状态未知"
            }
            
            if let error = error {
                print("❌ WCSession activation failed with error: \(error.localizedDescription)")
                self.lastMessage = "Watch连接失败: \(error.localizedDescription)"
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Log state change
        DispatchQueue.main.async {
            print("⚠️ iPhone WCSession Did Become Inactive")
            self.lastMessage = "Watch连接变为非活动"
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Log state change and attempt reactivation
        DispatchQueue.main.async {
            print("❌ iPhone WCSession Did Deactivate. Reactivating...")
            self.lastMessage = "Watch连接已断开，尝试重连..."
        }
        // Activation must be performed on a background thread
        DispatchQueue.global().async {
             WCSession.default.activate()
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Log message reception immediately
        DispatchQueue.main.async {
             print("🔵 iPhone didReceiveMessage: \(message["type"] ?? "Unknown Type")")
        }
        
        // 首先，检查消息类型
        let messageType = message["type"] as? String
        
        // 处理设置更新消息
        switch messageType {
        case "update_settings":
            DispatchQueue.main.async {
                // 更新 UserDefaults 中的设置
                if let feedbackType = message["feedbackType"] as? String {
                    UserDefaults.standard.set(feedbackType, forKey: "feedbackType")
                }
                if let peakThreshold = message["peakThreshold"] as? Double {
                    UserDefaults.standard.set(peakThreshold, forKey: "peakThreshold")
                }
                if let peakWindow = message["peakWindow"] as? Double {
                    UserDefaults.standard.set(peakWindow, forKey: "peakWindow")
                }
                if let gestureCooldownWindow = message["gestureCooldownWindow"] as? Double {
                    UserDefaults.standard.set(gestureCooldownWindow, forKey: "gestureCooldownWindow")
                }
                if let saveGestureData = message["saveGestureData"] as? Bool {
                    UserDefaults.standard.set(saveGestureData, forKey: "saveGestureData")
                }
                if let savePeaks = message["savePeaks"] as? Bool {
                    UserDefaults.standard.set(savePeaks, forKey: "savePeaks")
                }
                if let saveValleys = message["saveValleys"] as? Bool {
                    UserDefaults.standard.set(saveValleys, forKey: "saveValleys")
                }
                if let saveSelectedPeaks = message["saveSelectedPeaks"] as? Bool {
                    UserDefaults.standard.set(saveSelectedPeaks, forKey: "saveSelectedPeaks")
                }
                if let saveQuaternions = message["saveQuaternions"] as? Bool {
                    UserDefaults.standard.set(saveQuaternions, forKey: "saveQuaternions")
                }
                if let saveResultFile = message["saveResultFile"] as? Bool {
                    UserDefaults.standard.set(saveResultFile, forKey: "saveResultFile")
                }
                if let enableVisualFeedback = message["enableVisualFeedback"] as? Bool {
                    UserDefaults.standard.set(enableVisualFeedback, forKey: "enableVisualFeedback")
                }
                if let enableHapticFeedback = message["enableHapticFeedback"] as? Bool {
                    UserDefaults.standard.set(enableHapticFeedback, forKey: "enableHapticFeedback")
                }
                if let enableVoiceFeedback = message["enableVoiceFeedback"] as? Bool {
                    UserDefaults.standard.set(enableVoiceFeedback, forKey: "enableVoiceFeedback")
                }
                if let enableRealtimeData = message["enableRealtimeData"] as? Bool {
                    UserDefaults.standard.set(enableRealtimeData, forKey: "enableRealtimeData")
                }
                
                // 发送通知以更新设置视图
                NotificationCenter.default.post(name: NSNotification.Name("WatchSettingsUpdated"), object: nil, userInfo: message)
            }
        default:
            break
        }
        
        // 只处理非传感器数据的消息通知
        if messageType != "batch_data" && messageType != "sensor_data" {
            DispatchQueue.main.async {
                // 只打印非传感器数据的消息
                if messageType != nil {
                    print("iPhone收到消息(WCS): \(messageType!)") // 标记来源为 WCS
                }
                
                // 处理手势识别结果
                if messageType == "gesture_result",
                   let timestamp = message["timestamp"] as? Double,
                   let gesture = message["gesture"] as? String,
                   let confidence = message["confidence"] as? Double,
                   let peakValue = message["peakValue"] as? Double,
                   let id = message["id"] as? String {
                    
                    print("收到手势识别结果 - ID: \(id)")
                    print("当前动作状态 - 身体: \(self.currentBodyGesture), 手臂: \(self.currentArmGesture), 手指: \(self.currentFingerGesture)")
                    
                    // 确保使用当前选择的动作，而不是默认值
                    let bodyGesture = self.currentBodyGesture != "无" ? self.currentBodyGesture : "无"
                    let armGesture = self.currentArmGesture != "无" ? self.currentArmGesture : "无"
                    let fingerGesture = self.currentFingerGesture != "无" ? self.currentFingerGesture : "无"
                    
                    let result = GestureResult(
                        id: id,
                        timestamp: timestamp,
                        gesture: gesture,
                        confidence: confidence,
                        peakValue: peakValue,
                        trueGesture: gesture,
                        bodyGesture: bodyGesture,
                        armGesture: armGesture,
                        fingerGesture: fingerGesture
                    )
                    self.gestureResults.append(result)
                    print("创建手势结果 - 身体: \(result.bodyGesture), 手臂: \(result.armGesture), 手指: \(result.fingerGesture)")
                    
                    // 发送更新的手势结果到手表
                    let updatedMessage: [String: Any] = [
                        "type": "update_gesture_result",
                        "id": id,
                        "body_gesture": bodyGesture,
                        "arm_gesture": armGesture,
                        "finger_gesture": fingerGesture
                    ]
                    print("通过BLE发送动作更新到手表 - ID: \(id), 身体: \(bodyGesture), 手臂: \(armGesture), 手指: \(fingerGesture)")
                    BlePeripheralService.shared.sendJSONData(updatedMessage)
                    
                    // 记录当前的动作状态（合并为一行）
                    self.actionLogger.logGestureState(id: id, timestamp: timestamp, body: bodyGesture, arm: armGesture, finger: fingerGesture)
                    
                    // 不再发送更新消息到Watch
                } else if messageType == "stop_collection" {
                    self.resetState()
                }
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("ReceivedWatchMessage"),
                    object: nil,
                    userInfo: message
                )
            }
        } else if messageType == "batch_data",
                  let batchData = message["data"] as? [[String: Any]] {
            // 静默处理传感器数据，不打印任何日志
            do {
                let macMessage = ["type": "batch_data", "data": batchData] as [String : Any]
                let jsonData = try JSONSerialization.data(withJSONObject: macMessage, options: [.fragmentsAllowed])
                var dataWithNewline = jsonData
                dataWithNewline.append("\n".data(using: .utf8)!)
                sendDataToMac(dataWithNewline)
                
                // 只更新UI，不打印日志
                if let lastData = batchData.last {
                    if let accX = lastData["acc_x"] as? Double,
                       let accY = lastData["acc_y"] as? Double,
                       let accZ = lastData["acc_z"] as? Double,
                       let gyroX = lastData["gyro_x"] as? Double,
                       let gyroY = lastData["gyro_y"] as? Double,
                       let gyroZ = lastData["gyro_z"] as? Double {
                        
                        DispatchQueue.main.async {
                            self.lastReceivedData = [
                                "acc_x": accX,
                                "acc_y": accY,
                                "acc_z": accZ,
                                "gyro_x": gyroX,
                                "gyro_y": gyroY,
                                "gyro_z": gyroZ
                            ]
                            self.lastUpdateTime = Date()
                            
                            // 静默发送通知
                            NotificationCenter.default.post(
                                name: NSNotification.Name("ReceivedWatchMessage"),
                                object: nil,
                                userInfo: message
                            )
                        }
                    }
                }
            } catch {
                print("数据转换失败: \(error)")
            }
        }
    }
    
    func deleteResult(_ result: GestureResult) {
        // 从本地列表中删除
        if let index = gestureResults.firstIndex(where: { $0.id == result.id }) {
            gestureResults.remove(at: index)
            // 记录删除操作，使用结果的时间戳
            self.actionLogger.logDelete(id: result.id, timestamp: result.timestamp)
        }
        
        // 发送删除消息到 Watch
        let message = [
            "type": "delete_result",
            "id": result.id
        ]
        print("通过BLE发送删除消息 - ID: \(result.id)")
        BlePeripheralService.shared.sendJSONData(message)
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchDataPath = documentsPath.appendingPathComponent("WatchData", isDirectory: true)
        let logsPath = documentsPath.appendingPathComponent("Logs", isDirectory: true)
        let videosPath = documentsPath.appendingPathComponent("Videos", isDirectory: true)
        
        do {
            // 创建 WatchData 文件夹（如果不存在）
            if !FileManager.default.fileExists(atPath: watchDataPath.path) {
                try FileManager.default.createDirectory(at: watchDataPath, withIntermediateDirectories: true)
            }
            
            // 获取文件名和文件夹名
            guard let fileName = file.metadata?["name"] as? String,
                  let folderName = file.metadata?["folder"] as? String else {
                print("文件信息缺失")
                return
            }
            
            // 创建对应的文件夹
            let folderPath = watchDataPath.appendingPathComponent(folderName)
            if !FileManager.default.fileExists(atPath: folderPath.path) {
                try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)
            }
            
            let destinationURL = folderPath.appendingPathComponent(fileName)
            
            // 检查文件是否已存在
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                print("文件已存在: \(fileName)")
                return
            }
            
            // 移动文件到目标位置
            try FileManager.default.moveItem(at: file.fileURL, to: destinationURL)
            
            // 检查并复制对应的日志文件
            let logFileName = "\(folderName).log"
            let logSourceURL = logsPath.appendingPathComponent(logFileName)
            let logDestURL = folderPath.appendingPathComponent("actions.log")
            
            if FileManager.default.fileExists(atPath: logSourceURL.path) {
                print("找到对应的日志文件：\(logFileName)")
                if !FileManager.default.fileExists(atPath: logDestURL.path) {
                    try FileManager.default.copyItem(at: logSourceURL, to: logDestURL)
                    print("成功复制日志文件到数据文件夹")
                } else {
                    print("目标日志文件已存在")
                }
            } else {
                print("未找到对应的日志文件：\(logFileName)")
            }
            
            // 检查并复制对应的视频文件
            let videoFileName = "\(folderName).mp4"
            let videoSourceURL = videosPath.appendingPathComponent(videoFileName)
            let videoDestURL = folderPath.appendingPathComponent("record.mp4")
            
            if FileManager.default.fileExists(atPath: videoSourceURL.path) {
                print("找到对应的视频文件：\(videoFileName)")
                if !FileManager.default.fileExists(atPath: videoDestURL.path) {
                    try FileManager.default.copyItem(at: videoSourceURL, to: videoDestURL)
                    print("成功复制视频文件到数据文件夹")
                } else {
                    print("目标视频文件已存在")
                }
            } else {
                print("未找到对应的视频文件：\(videoFileName)")
            }
            
            DispatchQueue.main.async {
                self.lastMessage = "接收文件成功: \(fileName)"
            }
        } catch {
            print("处理接收文件失败: \(error)")
            DispatchQueue.main.async {
                self.lastMessage = "接收文件失败: \(error.localizedDescription)"
            }
        }
    }
    
    // 修改设置当前文件夹的方法
    func setCurrentFolder(_ url: URL) {
        actionLogger.setCurrentFolder(url)
    }
    
    // 修改关闭文件的方法
    func closeFiles() {
        actionLogger.closeFile()
    }
    
    // 添加打印文档目录路径的方法
    func printDocumentsPath() {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("文档目录路径：\(documentsPath.path)")
            let watchDataPath = documentsPath.appendingPathComponent("WatchData")
            print("WatchData文件夹路径：\(watchDataPath.path)")
            
            // 列出WatchData文件夹中的内容
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: watchDataPath, includingPropertiesForKeys: nil)
                print("WatchData文件夹内容：")
                for item in contents {
                    print("- \(item.lastPathComponent)")
                }
            } catch {
                print("读取WatchData文件夹内容失败：\(error)")
            }
        }
    }
    
    // 添加更新真实手势的方法
    func updateTrueGesture(id: String, gesture: String, timestamp: Double) {
        // 记录真实手势更新
        self.actionLogger.logTrueGestureUpdate(id: id, gesture: gesture, timestamp: timestamp)
    }
    
    // 添加更新文件夹名称和配置日志记录器的函数
    func updateFolderNameAndLogger(_ folderName: String) {
        DispatchQueue.main.async {
            self.currentFolderName = folderName
            print("更新文件夹名为: \(folderName)")

            // 更新日志文件名
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                // 创建 Logs 文件夹
                let logsPath = documentsPath.appendingPathComponent("Logs", isDirectory: true)
                do {
                    if !FileManager.default.fileExists(atPath: logsPath.path) {
                        try FileManager.default.createDirectory(at: logsPath, withIntermediateDirectories: true, attributes: nil)
                    }
                    // 使用新的文件夹名配置actionLogger
                    self.actionLogger.setCurrentFolder(logsPath, folderName: folderName)
                } catch {
                    print("创建 Logs 文件夹或设置 Logger 失败：\(error)")
                }
            }
        }
    }
}
