import Foundation
import WatchConnectivity
import Network
import QuartzCore

class SensorDataManager: NSObject, ObservableObject {
    static let shared = SensorDataManager()
    private var connection: NWConnection?
    private let serverPort: UInt16 = 12345 // Mac服务器端口
    private let serverHost = "10.144.34.42" // 替换为Mac的IP地址
    
    @Published var isConnected = false
    @Published var lastMessage = ""
    @Published var lastReceivedData: [String: Double] = [:]
    @Published var lastUpdateTime = Date()
    
    private var dataQueue = DispatchQueue(label: "com.wayne.dataQueue", qos: .userInteractive)
    private var lastSentTime: TimeInterval = 0
    private let minSendInterval: TimeInterval = 0.01  // 最小发送间隔，100Hz
    
    private var timestampHistory: [UInt64] = []
    private let maxHistorySize = 1000 // 记录更多样本用于统计
    private let minHistorySize = 100  // 最小保留样本数
    
    private override init() {
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
        }
    }
}

extension SensorDataManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            lastMessage = "Watch连接失败: \(error.localizedDescription)"
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if message["type"] as? String == "batch_data",
           let batchData = message["data"] as? [[String: Any]] {
            
            // 处理批量数据
            for (index, data) in batchData.enumerated() {
                if let timestamp = data["timestamp"] as? UInt64 {
                    // 只打印时间戳，用于验证采样率
//                    let timestampSeconds = Double(timestamp) / 1_000_000_000.0
//                    print("时间戳[\(index)]: \(timestampSeconds)秒")
                    
                    // 记录时间戳用于计算采样率
                    self.timestampHistory.append(timestamp)
                    if self.timestampHistory.count >= self.maxHistorySize {
                        self.timestampHistory = Array(self.timestampHistory.suffix(self.minHistorySize))
                    }
                }
                
                // 只用最后一帧更新UI
                if index == batchData.count - 1 {
                    if let accX = data["acc_x"] as? Double,
                       let accY = data["acc_y"] as? Double,
                       let accZ = data["acc_z"] as? Double,
                       let gyroX = data["gyro_x"] as? Double,
                       let gyroY = data["gyro_y"] as? Double,
                       let gyroZ = data["gyro_z"] as? Double {
                        
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
                
                // 发送数据到Mac
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: data)
                    var dataWithNewline = jsonData
                    dataWithNewline.append("\n".data(using: .utf8)!)
                    sendDataToMac(dataWithNewline)
                } catch {
                    print("数据转换失败: \(error)")
                }
            }
            
            // 计算并打印当前采样率
            if self.timestampHistory.count >= 2 {
                let timeSpanNs = Double(self.timestampHistory.last! - self.timestampHistory.first!)
                let timeSpanSeconds = timeSpanNs / 1_000_000_000.0
                let avgSamplingRate = Double(self.timestampHistory.count - 1) / timeSpanSeconds
                print("当前采样率: \(String(format: "%.1f Hz", avgSamplingRate))")
            }
        } else if message["type"] as? String == "stop_collection" {
            resetState()
        }
    }
}
