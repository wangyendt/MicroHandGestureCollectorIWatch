import Foundation
import WatchConnectivity
import CoreMotion

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    @Published var isSending = false
    @Published var lastMessage = ""
    private var messageQueue = DispatchQueue(label: "com.wayne.messageQueue")
    private var lastSentTime: TimeInterval = 0
    private let minSendInterval: TimeInterval = 0.005  // 最小发送间隔，100Hz
    
    @Published var lastTimestamp: UInt64 = 0
    @Published var samplingRate: Double = 0
    private var timestampHistory: [UInt64] = []
    private let maxHistorySize = 100 // 使用较小的缓存大小
    private let minHistorySize = 50  // 最小保留样本数
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendRealtimeData(accData: CMAcceleration, gyroData: CMRotationRate, timestamp: UInt64) {
        let currentTime = Date().timeIntervalSinceReferenceDate
        if currentTime - lastSentTime < minSendInterval {
            return  // 控制发送频率
        }
        
        guard WCSession.default.isReachable else {
            return
        }
        
        messageQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 使用同步块来保护数组操作
            DispatchQueue.main.sync {
                // 更新时间戳历史，使用滑动窗口方式
                self.timestampHistory.append(timestamp)
                if self.timestampHistory.count > self.maxHistorySize {
                    // 当超过最大容量时，只保留后面的minHistorySize个样本
                    self.timestampHistory = Array(self.timestampHistory.suffix(self.minHistorySize))
                }
                
                // 计算采样率
                if self.timestampHistory.count >= 2 {
                    let timeSpanNs = Double(self.timestampHistory.last! - self.timestampHistory.first!)
                    let timeSpanSeconds = timeSpanNs / 1_000_000_000.0
                    let samplingRate = Double(self.timestampHistory.count - 1) / timeSpanSeconds
                    
                    DispatchQueue.main.async {
                        self.samplingRate = samplingRate
                        self.lastTimestamp = timestamp
                    }
                }
            }
            
            let data: [String: Any] = [
                "type": "realtime_data",
                "timestamp": timestamp,
                "acc_x": accData.x,
                "acc_y": accData.y,
                "acc_z": accData.z,
                "gyro_x": gyroData.x,
                "gyro_y": gyroData.y,
                "gyro_z": gyroData.z
            ]
            
            WCSession.default.sendMessage(data, replyHandler: nil) { error in
                print("发送实时数据失败: \(error.localizedDescription)")
            }
            
            self.lastSentTime = currentTime
        }
    }
    
    func sendDataToPhone(fileURLs: [URL]) {
        guard WCSession.default.isReachable else {
            self.lastMessage = "iPhone 未连接"
            return
        }
        
        self.isSending = true
        
        // 创建一个临时文件夹用于存放合并的数据
        let temporaryDir = FileManager.default.temporaryDirectory
        let mergedFileURL = temporaryDir.appendingPathComponent("merged_data.txt")
        
        do {
            // 如果已存在则除
            if FileManager.default.fileExists(atPath: mergedFileURL.path) {
                try FileManager.default.removeItem(at: mergedFileURL)
            }
            
            // 创建新文件
            FileManager.default.createFile(atPath: mergedFileURL.path, contents: nil)
            
            // 合并所有文件内容
            var mergedData = Data()
            for fileURL in fileURLs {
                if let fileData = try? Data(contentsOf: fileURL) {
                    mergedData.append(fileData)
                    // 添加分隔符
                    if let separator = "\n---\n".data(using: .utf8) {
                        mergedData.append(separator)
                    }
                }
            }
            
            // 写入合并后的数据
            try mergedData.write(to: mergedFileURL)
            
            // 发送文件
            WCSession.default.transferFile(mergedFileURL, metadata: nil)
            self.lastMessage = "数据发送中..."
            
        } catch {
            self.lastMessage = "导出失败: \(error.localizedDescription)"
            print("Export error: \(error)")
        }
        
        self.isSending = false
    }
    
    // 添加重置状态的方法
    func resetState() {
        DispatchQueue.main.async {
            self.timestampHistory.removeAll()
            self.lastTimestamp = 0
            self.samplingRate = 0
            self.lastMessage = ""
            self.lastSentTime = 0
            
            // 发送停止采集消息到手机
            if WCSession.default.isReachable {
                let message = ["type": "stop_collection"]
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("发送停止采集消息失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.lastMessage = "传输失败: \(error.localizedDescription)"
            } else {
                self.lastMessage = "传输成功"
            }
        }
    }
} 
