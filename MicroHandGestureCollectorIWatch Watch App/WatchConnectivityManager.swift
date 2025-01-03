import Foundation
import WatchConnectivity
import CoreMotion

class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
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
    
    private var currentFolderURL: URL?
    
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
        var transferredCount = 0
        var skippedCount = 0
        
        for fileURL in fileURLs {
            do {
                // 检查是否是文件夹
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                    continue
                }
                
                if isDirectory.boolValue {
                    // 如果是文件夹，遍历其中的所有文件
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: fileURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                    
                    for contentURL in contents {
                        let metadata = [
                            "name": contentURL.lastPathComponent,
                            "folder": fileURL.lastPathComponent
                        ]
                        
                        WCSession.default.transferFile(contentURL, metadata: metadata)
                        transferredCount += 1
                        
                        DispatchQueue.main.async {
                            self.lastMessage = "正在传输: \(transferredCount) 个文件"
                        }
                    }
                } else {
                    // 如果是单个文件，直接发送
                    let metadata = [
                        "name": fileURL.lastPathComponent,
                        "folder": fileURL.deletingLastPathComponent().lastPathComponent
                    ]
                    
                    WCSession.default.transferFile(fileURL, metadata: metadata)
                    transferredCount += 1
                    
                    DispatchQueue.main.async {
                        self.lastMessage = "正在传输: \(transferredCount) 个文件"
                    }
                }
            } catch {
                print("Error processing file/folder: \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.isSending = false
            if skippedCount > 0 {
                self.lastMessage = "传输完成: \(transferredCount) 个文件，\(skippedCount) 个文件已存在"
            } else {
                self.lastMessage = "传输完成: \(transferredCount) 个文件"
            }
        }
    }
    
    // 添加重置状态的方法
    func resetState() {
        sendStopSignal()
    }
    
    func sendStopSignal() {
        // 立即发送停止信号到手机
        if WCSession.default.isReachable {
            let message: [String: Any] = [
                "type": "stop_collection" as String,
                "trigger_collection": true as Bool
            ]
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
    
    func setCurrentFolder(_ url: URL) {
        currentFolderURL = url
        print("Set current folder to: \(url.path)")
    }
    
    private func saveManualDeletedRecord(id: String, timestamp: UInt64, relativeTime: Double, gesture: String, confidence: Double) {
        guard let folderURL = currentFolderURL else {
            print("❌ No current folder set")
            return
        }
        
        let manualDeletedFileURL = folderURL.appendingPathComponent("manual_deleted.txt")
        print("📝 Saving manual deleted record to: \(manualDeletedFileURL.path)")
        
        // 如果文件不存在，创建文件并写入表头
        if !FileManager.default.fileExists(atPath: manualDeletedFileURL.path) {
            let header = "id,timestamp_ns,relative_timestamp_s,gesture,confidence\n"
            do {
                try header.write(to: manualDeletedFileURL, atomically: true, encoding: .utf8)
                print("Created new manual_deleted.txt file")
            } catch {
                print("Error creating manual_deleted.txt: \(error)")
                return
            }
        }
        
        // 构造记录字符串
        let recordString = String(format: "%@,%llu,%.3f,%@,%.3f\n",
                                id,
                                timestamp,
                                relativeTime,
                                gesture,
                                confidence)
        
        // 追加记录到文件
        if let data = recordString.data(using: .utf8) {
            do {
                let fileHandle = try FileHandle(forWritingTo: manualDeletedFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
                print("✅ Successfully saved manual deleted record")
            } catch {
                print("❌ Error saving manual deleted record: \(error)")
            }
        }
    }
    
    private func deleteResultFromFile(id: String) {
        guard let folderURL = currentFolderURL else {
            print("❌ No current folder set")
            return
        }
        
        let resultFileURL = folderURL.appendingPathComponent("result.txt")
        print("🔍 Looking for record in file: \(resultFileURL.path)")
        
        guard FileManager.default.fileExists(atPath: resultFileURL.path) else {
            print("❌ Result file not found at path: \(resultFileURL.path)")
            return
        }
        
        do {
            print("📝 Processing result file...")
            print("🗑 Looking for ID: \(id)")
            
            // 读取文件内容
            let content = try String(contentsOf: resultFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            print("📊 Total lines in file: \(lines.count)")
            
            // 查找要删除的记录
            for (index, line) in lines.enumerated() {
                if index == 0 || line.isEmpty { continue }
                
                let components = line.components(separatedBy: ",")
                if components.count >= 6 && components[5] == id {
                    // 找到匹配的记录，保存到manual_deleted.txt
                    if let timestamp = UInt64(components[0]),
                       let relativeTime = Double(components[1]),
                       let confidence = Double(components[3]) {
                        saveManualDeletedRecord(
                            id: id,
                            timestamp: timestamp,
                            relativeTime: relativeTime,
                            gesture: components[2],
                            confidence: confidence
                        )
                        print("✅ Found and processed record to delete")
                        return
                    }
                }
            }
            print("❌ No matching record found for ID: \(id)")
        } catch {
            print("❌ Error processing result file: \(error)")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // 重新激活会话
        WCSession.default.activate()
    }
    #endif
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Watch收到消息:", message)
        
        // 处理删除消息
        if let type = message["type"] as? String,
           type == "delete_result",
           let id = message["id"] as? String {
            print("收到删除请求，ID: \(id)")
            deleteResultFromFile(id: id)
        }
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ReceivedWatchMessage"),
                object: nil,
                userInfo: message
            )
        }
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
    
    func sendMessage(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("发送消息失败: \(error.localizedDescription)")
            }
        }
    }
} 
