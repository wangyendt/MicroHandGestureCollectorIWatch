import Foundation
import Network
import WatchConnectivity
import QuartzCore

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
    
    private var dataQueue = DispatchQueue(label: "com.wayne.dataQueue", qos: .userInteractive)
    private var lastSentTime: TimeInterval = 0
    private let minSendInterval: TimeInterval = 0.005  // 最小发送间隔，100Hz
    
    private var timestampHistory: [UInt64] = []
    private let maxHistorySize = 1000 // 记录更多样本用于统计
    private let minHistorySize = 100  // 最小保留样本数
    
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
    
    // 添加重置状态的方法
    func resetState() {
        DispatchQueue.main.async {
            self.timestampHistory.removeAll()
            self.lastReceivedData.removeAll()
            self.lastUpdateTime = Date()
            self.lastMessage = ""
            self.lastSentTime = 0
            self.gestureResults.removeAll()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            lastMessage = "Watch连接失败: \(error.localizedDescription)"
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // 首先，检查消息类型
        let messageType = message["type"] as? String
        
        // 处理设置更新消息
        if messageType == "update_settings" {
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
        }
        
        // 只处理非传感器数据的消息通知
        if messageType != "batch_data" && messageType != "sensor_data" {
            DispatchQueue.main.async {
                // 只打印非传感器数据的消息
                if messageType != nil {
                    print("iPhone收到消息: \(messageType!)")
                }
                
                // 处理手势识别结果
                if messageType == "gesture_result",
                   let timestamp = message["timestamp"] as? Double,
                   let gesture = message["gesture"] as? String,
                   let confidence = message["confidence"] as? Double,
                   let peakValue = message["peakValue"] as? Double,
                   let id = message["id"] as? String {
                    
                    let result = GestureResult(
                        id: id,
                        timestamp: timestamp,
                        gesture: gesture,
                        confidence: confidence,
                        peakValue: peakValue,
                        trueGesture: gesture
                    )
                    self.gestureResults.append(result)
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
        }
        
        // 发送删除消息到 Watch
        if WCSession.default.isReachable {
            let message = [
                "type": "delete_result",
                "id": result.id
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("发送删除消息失败: \(error.localizedDescription)")
            }
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchDataPath = documentsPath.appendingPathComponent("WatchData", isDirectory: true)
        
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
}
