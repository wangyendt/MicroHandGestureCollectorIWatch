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
    
    // 将这些属性改为公开，以便ContentView可以访问
    public var updatedTrueGestures: [String: String] = [:]
    public var updatedBodyGestures: [String: String] = [:]
    public var updatedArmGestures: [String: String] = [:]
    public var updatedFingerGestures: [String: String] = [:]
    
    // 添加 MotionManager 引用
    private var motionManager: MotionManager?
    
    // 定义负样本列表
    private let negativeGestures = ["其它"]
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // 添加设置 MotionManager 的方法
    func setMotionManager(_ manager: MotionManager) {
        self.motionManager = manager
    }
    
    func sendRealtimeData(accData: CMAcceleration, gyroData: CMRotationRate, timestamp: UInt64) {
        // 检查是否启用了实时数据发送
        guard UserDefaults.standard.bool(forKey: "enableRealtimeData") else {
            return
        }
        
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
        
        // 生成 manual_result.txt
        generateManualResult()
        
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
        let manualDeletedFileURL = folderURL.appendingPathComponent("manual_deleted.txt")
        
        print("🔍 Looking for record in file: \(resultFileURL.path)")
        
        guard FileManager.default.fileExists(atPath: resultFileURL.path) else {
            print("❌ Result file not found at path: \(resultFileURL.path)")
            return
        }
        
        // 首先检查是否已经在manual_deleted.txt中
        if FileManager.default.fileExists(atPath: manualDeletedFileURL.path) {
            do {
                let deletedContent = try String(contentsOf: manualDeletedFileURL, encoding: .utf8)
                let deletedLines = deletedContent.components(separatedBy: .newlines)
                for line in deletedLines {
                    let components = line.components(separatedBy: ",")
                    if components.count > 0 && components[0] == id {
                        print("⚠️ Record already marked as deleted: \(id)")
                        return
                    }
                }
            } catch {
                print("❌ Error checking manual_deleted.txt: \(error)")
            }
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
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        processMessage(message)
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
    
    private func generateManualResult() {
        guard let folderURL = currentFolderURL else {
            print("❌ No current folder set")
            return
        }

        let resultFileURL = folderURL.appendingPathComponent("result.txt")
        let manualResultFileURL = folderURL.appendingPathComponent("manual_result.txt")
        let statisticsFileURL = folderURL.appendingPathComponent("statistics.yaml")
        
        guard FileManager.default.fileExists(atPath: resultFileURL.path) else {
            print("❌ Result file not found")
            return
        }

        do {
            // 读取 result.txt
            let content = try String(contentsOf: resultFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            // 读取 manual_deleted.txt 中的已删除ID
            var deletedIds = Set<String>()
            let manualDeletedFileURL = folderURL.appendingPathComponent("manual_deleted.txt")
            if FileManager.default.fileExists(atPath: manualDeletedFileURL.path) {
                let deletedContent = try String(contentsOf: manualDeletedFileURL, encoding: .utf8)
                let deletedLines = deletedContent.components(separatedBy: .newlines)
                for line in deletedLines.dropFirst() { // 跳过表头
                    if !line.isEmpty {
                        let components = line.components(separatedBy: ",")
                        if components.count > 0 {
                            deletedIds.insert(components[0]) // ID是第一列
                        }
                    }
                }
            }
            
            // 创建 manual_result.txt
            var manualResultContent = "timestamp_ns,relative_timestamp_s,gesture,confidence,peak_value,id,true_gesture,is_deleted,body_gesture,arm_gesture,finger_gesture\n"
            
            // 统计变量
            var gestureCounts: [String: Int] = [:]
            var correctCounts: [String: Int] = [:]
            var totalCount = 0
            var totalCorrect = 0
            var positiveCount = 0  // 正样本总数
            var predictedPositiveCount = 0  // 预测为正样本的总数
            var truePositiveCount = 0  // 预测正确的正样本数
            
            for line in lines.dropFirst() { // 跳过表头
                if line.isEmpty { continue }
                
                let components = line.components(separatedBy: ",")
                if components.count >= 6 {  // 修改这里，因为result.txt现在只有6列
                    let id = components[5]
                    let isDeleted = deletedIds.contains(id)
                    let predictedGesture = components[2]
                    let trueGesture = updatedTrueGestures[id] ?? predictedGesture
                    let bodyGesture = updatedBodyGestures[id] ?? "无"  // 使用updatedBodyGestures中的值或默认值
                    let armGesture = updatedArmGestures[id] ?? "无"    // 使用updatedArmGestures中的值或默认值
                    let fingerGesture = updatedFingerGestures[id] ?? "无"  // 使用updatedFingerGestures中的值或默认值
                    
                    manualResultContent += "\(components[0]),\(components[1]),\(components[2]),\(components[3]),\(components[4]),\(id),\(trueGesture),\(isDeleted ? "1" : "0"),\(bodyGesture),\(armGesture),\(fingerGesture)\n"
                    
                    // 只统计未删除的结果
                    if !isDeleted {
                        gestureCounts[trueGesture, default: 0] += 1
                        totalCount += 1
                        
                        // 计算正负样本相关统计
                        if !negativeGestures.contains(trueGesture) {
                            positiveCount += 1  // 真实标签为正样本
                        }
                        if !negativeGestures.contains(predictedGesture) {
                            predictedPositiveCount += 1  // 预测为正样本
                            if predictedGesture == trueGesture {
                                truePositiveCount += 1  // 预测正确的正样本
                            }
                        }
                        
                        if predictedGesture == trueGesture {
                            correctCounts[trueGesture, default: 0] += 1
                            totalCorrect += 1
                        }
                    }
                }
            }
            
            // 计算各项指标
            let accuracy = totalCount > 0 ? Double(totalCorrect) / Double(totalCount) : 0.0
            let recall = positiveCount > 0 ? Double(truePositiveCount) / Double(positiveCount) : 0.0
            let precision = predictedPositiveCount > 0 ? Double(truePositiveCount) / Double(predictedPositiveCount) : 0.0
            
            // 生成统计信息的YAML内容
            var statisticsContent = "statistics:\n"
            statisticsContent += "  total_samples: \(totalCount)\n"
            statisticsContent += "  total_correct: \(totalCorrect)\n"
            statisticsContent += "  overall_accuracy: \(String(format: "%.4f", accuracy))\n"
            statisticsContent += "  positive_recall: \(String(format: "%.4f", recall))\n"
            statisticsContent += "  positive_precision: \(String(format: "%.4f", precision))\n"
            statisticsContent += "  gestures:\n"
            
            // 按手势名称排序
            for gesture in gestureCounts.keys.sorted() {
                let count = gestureCounts[gesture] ?? 0
                let correct = correctCounts[gesture] ?? 0
                let accuracy = count > 0 ? Double(correct) / Double(count) : 0.0
                statisticsContent += "    \(gesture):\n"
                statisticsContent += "      count: \(count)\n"
                statisticsContent += "      correct: \(correct)\n"
                statisticsContent += "      accuracy: \(String(format: "%.4f", accuracy))\n"
            }
            
            // 写入文件
            try manualResultContent.write(to: manualResultFileURL, atomically: true, encoding: .utf8)
            try statisticsContent.write(to: statisticsFileURL, atomically: true, encoding: .utf8)
            print("✅ Successfully generated manual_result.txt and statistics.yaml")
            
        } catch {
            print("❌ Error generating result files: \(error)")
        }
    }
    
    // 添加连接刷新功能
    func refreshConnection() {
        if WCSession.default.activationState != .activated {
            print("Watch连接未激活，尝试重新激活")
            WCSession.default.activate()
        } else if !WCSession.default.isReachable {
            print("iPhone暂时不可达，尝试刷新连接")
            // 发送一个空消息触发连接刷新
            let pingMessage: [String: Any] = ["type": "ping", "timestamp": Date().timeIntervalSince1970]
            WCSession.default.sendMessage(pingMessage, replyHandler: { _ in
                print("连接刷新成功，iPhone可达")
            }, errorHandler: { error in
                print("发送ping消息失败: \(error.localizedDescription)")
            })
        } else {
            print("WatchConnectivity连接状态良好")
        }
    }
    
    // MARK: - 统一消息处理
    
    /// 统一处理从各种渠道收到的消息（WCSession, BLE等）
    func processMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String {
            print("处理消息类型: \(type)")
            
            switch type {
            case "start_collection":
                handleStartCollection(message)
            case "stop_collection":
                handleStopCollection(message)
            case "request_export":
                handleRequestExport(message)
            case "update_settings":
                handleUpdateSettings(message)
            case "update_true_gesture":
                handleUpdateTrueGesture(message)
            case "update_body_gesture":
                handleUpdateBodyGesture(message)
            case "update_arm_gesture":
                handleUpdateArmGesture(message)
            case "update_finger_gesture":
                handleUpdateFingerGesture(message)
            case "delete_result":
                handleDeleteResult(message)
            case "update_gesture_result":
                handleUpdateGestureResult(message)
            case "phone_start_timestamp":
                handlePhoneStartTimestamp(message)
            default:
                print("未知消息类型: \(type)")
            }
        }
        
        // 通知UI更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ReceivedWatchMessage"),
                object: nil,
                userInfo: message
            )
        }
    }
    
    // MARK: - 消息处理实现
    
    private func handleStartCollection(_ message: [String: Any]) {
        NotificationCenter.default.post(
            name: NSNotification.Name("StartCollectionRequested"),
            object: nil,
            userInfo: message
        )
    }
    
    private func handleStopCollection(_ message: [String: Any]) {
        NotificationCenter.default.post(
            name: NSNotification.Name("StopCollectionRequested"),
            object: nil,
            userInfo: message
        )
    }
    
    private func handleRequestExport(_ message: [String: Any]) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ExportDataRequested"),
            object: nil,
            userInfo: message
        )
    }
    
    private func handleUpdateSettings(_ message: [String: Any]) {
        DispatchQueue.main.async {
            // 更新本地设置
            if let feedbackType = message["feedbackType"] as? String {
                print("更新反馈类型为: \(feedbackType)")
                UserDefaults.standard.set(feedbackType, forKey: "feedbackType")
                // 确保设置已保存
                UserDefaults.standard.synchronize()
            }
            if let peakThreshold = message["peakThreshold"] as? Double {
                UserDefaults.standard.set(peakThreshold, forKey: "peakThreshold")
                self.motionManager?.signalProcessor.updateSettings(peakThreshold: peakThreshold)
            }
            if let peakWindow = message["peakWindow"] as? Double {
                UserDefaults.standard.set(peakWindow, forKey: "peakWindow")
                self.motionManager?.signalProcessor.updateSettings(peakWindow: peakWindow)
            }
            if let saveGestureData = message["saveGestureData"] as? Bool {
                UserDefaults.standard.set(saveGestureData, forKey: "saveGestureData")
                self.motionManager?.updateSaveSettings(gestureData: saveGestureData)
            }
            if let savePeaks = message["savePeaks"] as? Bool {
                UserDefaults.standard.set(savePeaks, forKey: "savePeaks")
                self.motionManager?.updateSaveSettings(peaks: savePeaks)
            }
            if let saveValleys = message["saveValleys"] as? Bool {
                UserDefaults.standard.set(saveValleys, forKey: "saveValleys")
                self.motionManager?.updateSaveSettings(valleys: saveValleys)
            }
            if let saveSelectedPeaks = message["saveSelectedPeaks"] as? Bool {
                UserDefaults.standard.set(saveSelectedPeaks, forKey: "saveSelectedPeaks")
                self.motionManager?.updateSaveSettings(selectedPeaks: saveSelectedPeaks)
            }
            if let saveQuaternions = message["saveQuaternions"] as? Bool {
                UserDefaults.standard.set(saveQuaternions, forKey: "saveQuaternions")
                self.motionManager?.updateSaveSettings(quaternions: saveQuaternions)
            }
            if let saveResultFile = message["saveResultFile"] as? Bool {
                UserDefaults.standard.set(saveResultFile, forKey: "saveResultFile")
                self.motionManager?.updateSaveSettings(resultFile: saveResultFile)
            }
            if let enableVisualFeedback = message["enableVisualFeedback"] as? Bool {
                UserDefaults.standard.set(enableVisualFeedback, forKey: "enableVisualFeedback")
                FeedbackManager.enableVisualFeedback = enableVisualFeedback
            }
            if let enableHapticFeedback = message["enableHapticFeedback"] as? Bool {
                UserDefaults.standard.set(enableHapticFeedback, forKey: "enableHapticFeedback")
                FeedbackManager.enableHapticFeedback = enableHapticFeedback
            }
            if let enableVoiceFeedback = message["enableVoiceFeedback"] as? Bool {
                UserDefaults.standard.set(enableVoiceFeedback, forKey: "enableVoiceFeedback")
                FeedbackManager.enableVoiceFeedback = enableVoiceFeedback
            }
            if let enableRealtimeData = message["enableRealtimeData"] as? Bool {
                print("更新实时数据设置为: \(enableRealtimeData)")
                UserDefaults.standard.set(enableRealtimeData, forKey: "enableRealtimeData")
            }
        }
    }
    
    private func handleUpdateTrueGesture(_ message: [String: Any]) {
        if let id = message["id"] as? String,
           let trueGesture = message["true_gesture"] as? String {
            print("收到真实手势更新，ID: \(id), 真实手势: \(trueGesture)")
            updatedTrueGestures[id] = trueGesture
        }
    }
    
    private func handleUpdateBodyGesture(_ message: [String: Any]) {
        if let id = message["id"] as? String,
           let bodyGesture = message["body_gesture"] as? String {
            print("收到身体动作更新，ID: \(id), 身体动作: \(bodyGesture)")
            updatedBodyGestures[id] = bodyGesture
        }
    }
    
    private func handleUpdateArmGesture(_ message: [String: Any]) {
        if let id = message["id"] as? String,
           let armGesture = message["arm_gesture"] as? String {
            print("收到手臂动作更新，ID: \(id), 手臂动作: \(armGesture)")
            updatedArmGestures[id] = armGesture
        }
    }
    
    private func handleUpdateFingerGesture(_ message: [String: Any]) {
        if let id = message["id"] as? String,
           let fingerGesture = message["finger_gesture"] as? String {
            print("收到手指动作更新，ID: \(id), 手指动作: \(fingerGesture)")
            updatedFingerGestures[id] = fingerGesture
        }
    }
    
    private func handleDeleteResult(_ message: [String: Any]) {
        if let id = message["id"] as? String {
            // 使用通知中心通知ContentView处理删除请求
            NotificationCenter.default.post(
                name: NSNotification.Name("DeleteResultRequested"),
                object: nil,
                userInfo: message
            )
        }
    }
    
    private func handleUpdateGestureResult(_ message: [String: Any]) {
        if let id = message["id"] as? String,
           let bodyGesture = message["body_gesture"] as? String,
           let armGesture = message["arm_gesture"] as? String,
           let fingerGesture = message["finger_gesture"] as? String {
            print("收到动作更新 - ID: \(id)")
            print("动作信息 - 身体: \(bodyGesture), 手臂: \(armGesture), 手指: \(fingerGesture)")
            updatedBodyGestures[id] = bodyGesture
            updatedArmGestures[id] = armGesture
            updatedFingerGestures[id] = fingerGesture
            print("已更新动作字典")
        }
    }
    
    // 添加处理时间戳消息的方法
    private func handlePhoneStartTimestamp(_ message: [String: Any]) {
        if let timestamp = message["timestamp"] as? TimeInterval {
            print("收到手机端开始时间戳：\(timestamp)")
            motionManager?.setTimestampOffset(timestamp)
        }
    }
} 
