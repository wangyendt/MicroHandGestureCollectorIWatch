import Foundation
import WatchConnectivity
import Network

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
        if message["type"] as? String == "realtime_data" {
            // 更新UI数据
            DispatchQueue.main.async {
                if let accX = message["acc_x"] as? Double,
                   let accY = message["acc_y"] as? Double,
                   let accZ = message["acc_z"] as? Double,
                   let gyroX = message["gyro_x"] as? Double,
                   let gyroY = message["gyro_y"] as? Double,
                   let gyroZ = message["gyro_z"] as? Double {
                    
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
            
            // 发送数据到Mac
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: message)
                var dataWithNewline = jsonData
                dataWithNewline.append("\n".data(using: .utf8)!)
                sendDataToMac(dataWithNewline)
            } catch {
                print("数据转换失败: \(error)")
            }
        }
    }
}
