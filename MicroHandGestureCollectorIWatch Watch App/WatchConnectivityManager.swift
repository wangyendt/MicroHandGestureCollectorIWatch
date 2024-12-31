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
    
    private var dataBuffer: [(CMAcceleration, CMRotationRate, UInt64)] = []
    private let batchSize = 10  // 每5个样本发送一次
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendRealtimeData(accData: CMAcceleration, gyroData: CMRotationRate, timestamp: UInt64) {
        // 使用异步方式更新时间戳历史
        DispatchQueue.main.async {
            // 更新时间戳历史，使用滑动窗口方式
            self.timestampHistory.append(timestamp)
            if self.timestampHistory.count > self.maxHistorySize {
                self.timestampHistory = Array(self.timestampHistory.suffix(self.minHistorySize))
            }
            
            // 计算采样率
            if self.timestampHistory.count >= 2 {
                let timeSpanNs = Double(self.timestampHistory.last! - self.timestampHistory.first!)
                let timeSpanSeconds = timeSpanNs / 1_000_000_000.0
                let samplingRate = Double(self.timestampHistory.count - 1) / timeSpanSeconds
                
                self.samplingRate = samplingRate
                self.lastTimestamp = timestamp
            }
        }
        
        // 数据缓冲处理放在单独的队列中
        messageQueue.async {
            self.dataBuffer.append((accData, gyroData, timestamp))
            
            if self.dataBuffer.count >= self.batchSize {
                let batchData: [[String: Any]] = self.dataBuffer.map { acc, gyro, ts in
                    let data: [String: Any] = [
                        "timestamp": ts,
                        "acc_x": acc.x,
                        "acc_y": acc.y,
                        "acc_z": acc.z,
                        "gyro_x": gyro.x,
                        "gyro_y": gyro.y,
                        "gyro_z": gyro.z
                    ]
                    return data
                }
                
                let message: [String: Any] = [
                    "type": "batch_data",
                    "data": batchData
                ]
                
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("发送批量数据失败: \(error.localizedDescription)")
                }
                
                self.dataBuffer.removeAll()
            }
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
        sendStopSignal()
    }
    
    func sendStopSignal() {
        // 立即发送停止信号到手机
        if WCSession.default.isReachable {
            let message = ["type": "stop_collection"]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("发送停止采集消息失败: \(error.localizedDescription)")
            }
        }
        
        // 然后清除本地状态
        DispatchQueue.main.async {
            self.timestampHistory.removeAll()
            self.lastTimestamp = 0
            self.samplingRate = 0
            self.lastMessage = ""
            self.lastSentTime = 0
            self.dataBuffer.removeAll()
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
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if message["type"] as? String == "delete_result",
           let idToDelete = message["id"] as? String {
            deleteResultFromFile(id: idToDelete)
        }
    }
    
    private func deleteResultFromFile(id: String) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            // 遍历所有文件夹
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            for folderURL in fileURLs where folderURL.hasDirectoryPath {
                let resultFileURL = folderURL.appendingPathComponent("result.txt")
                
                if FileManager.default.fileExists(atPath: resultFileURL.path) {
                    // 读取文件内容
                    let content = try String(contentsOf: resultFileURL, encoding: .utf8)
                    let lines = content.components(separatedBy: .newlines)
                    
                    // 过滤掉要删除的行，同时保留表头
                    var newLines = lines.enumerated().filter { index, line in
                        index == 0 || !line.contains(id)  // 保留第一行（表头）和不包含要删除ID的行
                    }.map { $0.element }
                    
                    // 确保最后一行没有多余的换行符
                    if let last = newLines.last, last.isEmpty {
                        newLines.removeLast()
                    }
                    
                    // 写回文件
                    let newContent = newLines.joined(separator: "\n") + "\n"
                    try newContent.write(to: resultFileURL, atomically: true, encoding: .utf8)
                    print("Deleted result with ID: \(id) from file")
                }
            }
        } catch {
            print("Error deleting result: \(error)")
        }
    }
} 
