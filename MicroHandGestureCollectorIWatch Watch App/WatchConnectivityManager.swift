import Foundation
import WatchConnectivity
import CoreMotion

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    @Published var isSending = false
    @Published var lastMessage = ""
    private var messageQueue = DispatchQueue(label: "com.wayne.messageQueue")
    private var lastSentTime: TimeInterval = 0
    private let minSendInterval: TimeInterval = 0.01  // 最小发送间隔，100Hz
    
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
            
            self?.lastSentTime = currentTime
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