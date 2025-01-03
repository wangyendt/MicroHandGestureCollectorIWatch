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
        // 首先，转发所有消息到 NotificationCenter
        DispatchQueue.main.async {
            // 只打印控制消息的日志，不打印传感器数据
            if let type = message["type"] as? String,
               type != "batch_data" && type != "sensor_data" && type != "gesture_result" {
                print("iPhone收到消息:", message)
            }
            
            // 处理手势识别结果
            if message["type"] as? String == "gesture_result",
               let timestamp = message["timestamp"] as? Double,
               let gesture = message["gesture"] as? String,
               let confidence = message["confidence"] as? Double,
               let peakValue = message["peakValue"] as? Double,
               let id = message["id"] as? String {
                
                DispatchQueue.main.async {
                    let result = GestureResult(
                        id: id,
                        timestamp: timestamp,
                        gesture: gesture,
                        confidence: confidence,
                        peakValue: peakValue,
                        trueGesture: gesture  // 初始时使用识别的手势作为真实手势
                    )
                    self.gestureResults.append(result)
                }
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("ReceivedWatchMessage"),
                object: nil,
                userInfo: message
            )
        }
        
        // 然后处理传感器数据
        if message["type"] as? String == "batch_data",
           let batchData = message["data"] as? [[String: Any]] {
            
            // 检查丢帧（只在丢帧时打印日志）
            for i in 1..<batchData.count {
                if let prevTimestamp = batchData[i-1]["timestamp"] as? UInt64,
                   let currTimestamp = batchData[i]["timestamp"] as? UInt64 {
                    let timeDiff = Double(currTimestamp - prevTimestamp) / 1_000_000.0 // 转换为毫秒
                    if timeDiff > 13.0 { // 超过13ms认为丢帧
                        print("丢帧: \(String(format: "%.2f", timeDiff))ms between frames")
                    }
                }
            }
            
            // 直接转发批量数据到Mac
            do {
                let macMessage: [String: Any] = [
                    "type": "batch_data",
                    "data": batchData
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: macMessage)
                var dataWithNewline = jsonData
                dataWithNewline.append("\n".data(using: .utf8)!)
                sendDataToMac(dataWithNewline)
            } catch {
                print("数据转换失败: \(error)")
            }
            
            // UI 更新代码保持不变
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
                    }
                }
            }
        } else if message["type"] as? String == "stop_collection" {
            resetState()
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
