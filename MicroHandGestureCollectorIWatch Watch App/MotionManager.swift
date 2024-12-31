//
//  MotionManager.swift
//  MicroHandGestureCollectorWatchOS
//
//  Created by wayne on 2024/11/4.
//

import SwiftUI
import CoreMotion
import Combine
import os.log
import WatchKit

#if os(watchOS)
public class MotionManager: ObservableObject, SignalProcessorDelegate {
    @Published private(set) var accelerationData: CMAcceleration?
    @Published private(set) var rotationData: CMRotationRate?
    private let motionManager: CMMotionManager
    private var accFileHandle: FileHandle?
    private var gyroFileHandle: FileHandle?
    private var peakFileHandle: FileHandle?
    private var valleyFileHandle: FileHandle?
    private var selectedPeakFileHandle: FileHandle?
    private var quaternionFileHandle: FileHandle?
    private var isCollecting = false
    private var logger: OSLog
    
    @Published var isReady = true
    
    // 添加文件写入队列
    private let fileWriteQueue = DispatchQueue(label: "com.wayne.fileWriteQueue", qos: .utility)
    
    // 添加数据缓冲区
    private var dataBuffer: [(timestamp: UInt64, acc: (x: Double, y: Double, z: Double), gyro: (x: Double, y: Double, z: Double))] = []
    private let bufferSize = 10 // 每10个数据点写入一次文件
    
    public let signalProcessor: SignalProcessor
    
    // 添加数据保存控制变量
    private var savePeaks: Bool = false
    private var saveValleys: Bool = false
    private var saveSelectedPeaks: Bool = false
    private var saveQuaternions: Bool = false
    private var saveGestureData: Bool = false
    
    // 添加可观察的计数属性
    @Published private(set) var peakCount: Int = 0
    
    public init() {
        logger = OSLog(subsystem: "wayne.MicroHandGestureCollectorIWatch.watchkitapp", category: "sensors")
        motionManager = CMMotionManager()
        
        // 从 UserDefaults 读取保存的设置
        let threshold = UserDefaults.standard.double(forKey: "peakThreshold")
        let window = UserDefaults.standard.double(forKey: "peakWindow")
        
        signalProcessor = SignalProcessor(
            peakThreshold: threshold > 0 ? threshold : 0.3,
            peakWindow: window > 0 ? window : 0.6
        )
        
        // 设置代理
        signalProcessor.delegate = self
        
        print("MotionManager 初始化")
        print("加速度计状态: \(motionManager.isAccelerometerAvailable ? "可用" : "不可用")")
        print("陀螺仪状态: \(motionManager.isGyroAvailable ? "可用" : "不可用")")
        print("设备运动状态: \(motionManager.isDeviceMotionAvailable ? "可用" : "不可用")")
        
        // 从 UserDefaults 读取所有保存设置的初始值
        savePeaks = UserDefaults.standard.bool(forKey: "savePeaks")
        saveValleys = UserDefaults.standard.bool(forKey: "saveValleys")
        saveSelectedPeaks = UserDefaults.standard.bool(forKey: "saveSelectedPeaks")
        saveQuaternions = UserDefaults.standard.bool(forKey: "saveQuaternions")
        saveGestureData = UserDefaults.standard.bool(forKey: "saveGestureData")  // 默认为 false
        
        // 初始化时就更新 GestureRecognizer 的设置
        signalProcessor.gestureRecognizer.updateSettings(saveGestureData: saveGestureData)
    }
    
    // 实现代理方法
    public func signalProcessor(_ processor: SignalProcessor, didDetectStrongPeak value: Double) {
        // 触发振动、视觉和语音反馈
        FeedbackManager.playFeedback(
            style: .success,
            speak: "\(processor.selectedPeakCount)"
        )
        peakCount = processor.selectedPeakCount
    }
    
    public func signalProcessor(_ processor: SignalProcessor, didDetectPeak timestamp: TimeInterval, value: Double) {
        savePeak(timestamp: UInt64(timestamp * 1_000_000_000), value: value)
    }
    
    public func signalProcessor(_ processor: SignalProcessor, didDetectValley timestamp: TimeInterval, value: Double) {
        saveValley(timestamp: UInt64(timestamp * 1_000_000_000), value: value)
    }
    
    public func signalProcessor(_ processor: SignalProcessor, didSelectPeak timestamp: TimeInterval, value: Double) {
        saveSelectedPeak(timestamp: UInt64(timestamp * 1_000_000_000), value: value)
    }
    
    public func signalProcessor(_ processor: SignalProcessor, didRecognizeGesture gesture: String, confidence: Double) {
        // 处理识别结果
        print("识别到手势: \(gesture), 置信度: \(confidence)")
        
        // 可以触发反馈
        // FeedbackManager.playFeedback(
        //     style: .success,
        //     speak: "识别到\(gesture)"
        // )
    }
    
    public func startDataCollection(name: String, hand: String, gesture: String, force: String, note: String) {
        signalProcessor.resetCount()  // 重置计数
        signalProcessor.resetStartTime()  // 重置开始时间
        peakCount = 0
        // 设置更新间隔
        motionManager.accelerometerUpdateInterval = 1.0 / 200.0  // 200Hz
        motionManager.gyroUpdateInterval = 1.0 / 200.0  // 200Hz
        
        // 创建文件夹和文件
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // 使用新的文件命名格式
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        let dateString = dateFormatter.string(from: Date())
        
        // 创建文件夹名称
        let folderName = "\(dateString)_\(name)_\(hand)_\(gesture)_\(force)_\(note)"
        let folderURL = documentsPath.appendingPathComponent(folderName)
        
        // 创建文件夹
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            
            // 创建必需的文件
            let accFileURL = folderURL.appendingPathComponent("acc.txt")
            let gyroFileURL = folderURL.appendingPathComponent("gyro.txt")
            
            // 根据设置创建可选文件
            let peakFileURL = savePeaks ? folderURL.appendingPathComponent("peak.txt") : nil
            let valleyFileURL = saveValleys ? folderURL.appendingPathComponent("valley.txt") : nil
            let selectedPeakFileURL = saveSelectedPeaks ? folderURL.appendingPathComponent("selected_peak.txt") : nil
            let quaternionFileURL = saveQuaternions ? folderURL.appendingPathComponent("quaternion.txt") : nil
            
            // 创建必需的文件头部信息
            let accHeader = "timestamp_ns,acc_x,acc_y,acc_z\n"
            let gyroHeader = "timestamp_ns,gyro_x,gyro_y,gyro_z\n"
            
            // 写入必需的文件头部信息
            try accHeader.write(to: accFileURL, atomically: true, encoding: .utf8)
            try gyroHeader.write(to: gyroFileURL, atomically: true, encoding: .utf8)
            
            // 根据设置写入可选文件头部信息
            if savePeaks {
                let peakHeader = "timestamp_ns,value\n"
                try peakHeader.write(to: peakFileURL!, atomically: true, encoding: .utf8)
            }
            if saveValleys {
                let valleyHeader = "timestamp_ns,value\n"
                try valleyHeader.write(to: valleyFileURL!, atomically: true, encoding: .utf8)
            }
            if saveSelectedPeaks {
                let selectedPeakHeader = "timestamp_ns,value\n"
                try selectedPeakHeader.write(to: selectedPeakFileURL!, atomically: true, encoding: .utf8)
            }
            if saveQuaternions {
                let quaternionHeader = "timestamp_ns,w,x,y,z\n"
                try quaternionHeader.write(to: quaternionFileURL!, atomically: true, encoding: .utf8)
            }
            
            // 打开必需的文件句柄
            accFileHandle = try FileHandle(forWritingTo: accFileURL)
            gyroFileHandle = try FileHandle(forWritingTo: gyroFileURL)
            
            // 根据设置打开可选文件句柄
            if savePeaks {
                peakFileHandle = try FileHandle(forWritingTo: peakFileURL!)
            }
            if saveValleys {
                valleyFileHandle = try FileHandle(forWritingTo: valleyFileURL!)
            }
            if saveSelectedPeaks {
                selectedPeakFileHandle = try FileHandle(forWritingTo: selectedPeakFileURL!)
            }
            if saveQuaternions {
                quaternionFileHandle = try FileHandle(forWritingTo: quaternionFileURL!)
            }
            
            // 移动到文件末尾
            accFileHandle?.seekToEndOfFile()
            gyroFileHandle?.seekToEndOfFile()
            peakFileHandle?.seekToEndOfFile()
            valleyFileHandle?.seekToEndOfFile()
            selectedPeakFileHandle?.seekToEndOfFile()
            quaternionFileHandle?.seekToEndOfFile()
        } catch {
            print("Error creating directory or files: \(error)")
            return
        }
        
        var lastTimestamp: UInt64 = 0
        
        var printCounter = 0
        // 开始收集数据
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            let timestamp = UInt64(motion.timestamp * 1_000_000_000)
            
            // 检查丢帧
            if lastTimestamp != 0 {
                let timeDiff = Double(timestamp - lastTimestamp) / 1_000_000.0
                if timeDiff > 13.0 {
                    print("Watch丢帧: \(String(format: "%.2f", timeDiff))ms between frames")
                }
            }
            lastTimestamp = timestamp
            
            // 计算总加速度（保持原有的计算方式）
            let totalAccX = motion.gravity.x * 9.81 + motion.userAcceleration.x * 9.81
            let totalAccY = motion.gravity.y * 9.81 + motion.userAcceleration.y * 9.81
            let totalAccZ = motion.gravity.z * 9.81 + motion.userAcceleration.z * 9.81

            // 更新UI数据（使用总加速度）
            self?.accelerationData = CMAcceleration(x: totalAccX, y: totalAccY, z: totalAccZ)
            self?.rotationData = motion.rotationRate

            // 计算总加速度范数并进行峰值检测
            let accNorm = self?.signalProcessor.calculateNorm(
                x: totalAccX,
                y: totalAccY,
                z: totalAccZ
            ) ?? 0.0

            // 传递原始数据给 SignalProcessor
            self?.signalProcessor.processNewPoint(
                timestamp: motion.timestamp,
                accNorm: accNorm,
                acc: (totalAccX, totalAccY, totalAccZ),
                gyro: (motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
            )

            // 保存四元数
            if let quaternion = self?.signalProcessor.getCurrentQuaternion() {
                self?.saveQuaternion(timestamp: timestamp, quaternion: quaternion)
            }
            
            // 获取检测到的峰值（如果需要使用）
            let peaks = self?.signalProcessor.getRecentPeaks() ?? []
            
            // 将数据添加到缓冲区
            self?.dataBuffer.append((
                timestamp: timestamp,
                acc: (x: totalAccX, y: totalAccY, z: totalAccZ),
                gyro: (x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z)
            ))
            
            // 当缓冲区达到指定大小时，异步写入文件
            if self?.dataBuffer.count ?? 0 >= self?.bufferSize ?? 10 {
                let dataToWrite = self?.dataBuffer ?? []
                self?.dataBuffer.removeAll()
                
                self?.fileWriteQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    var accData = Data()
                    var gyroData = Data()
                    
                    for point in dataToWrite {
                        let accString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                             point.timestamp,
                                             point.acc.x,
                                             point.acc.y,
                                             point.acc.z)
                        
                        let gyroString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                              point.timestamp,
                                              point.gyro.x,
                                              point.gyro.y,
                                              point.gyro.z)
                        
                        if let accDataPoint = accString.data(using: .utf8),
                           let gyroDataPoint = gyroString.data(using: .utf8) {
                            accData.append(accDataPoint)
                            gyroData.append(gyroDataPoint)
                        }
                    }
                    
                    self.accFileHandle?.write(accData)
                    self.gyroFileHandle?.write(gyroData)
                }
            }
            
            // 发送数据到手机
            WatchConnectivityManager.shared.sendRealtimeData(
                accData: CMAcceleration(x: totalAccX, y: totalAccY, z: totalAccZ),
                gyroData: motion.rotationRate,
                timestamp: timestamp
            )
            
            // 每100帧打印一次状态
            printCounter += 1
            if printCounter >= 100 {
//                self?.signalProcessor.printStatus()
                printCounter = 0
            }
        }
        
        isCollecting = true
        
        // 创建文件夹后，设置 SignalProcessor 的当前文件夹
        signalProcessor.setCurrentFolder(folderURL)
        print("Set folder for SignalProcessor: \(folderURL.path)")
        
        // 确保设置被正确应用
        signalProcessor.gestureRecognizer.updateSettings(saveGestureData: saveGestureData)
        print("Applied gesture data saving setting: \(saveGestureData)")
    }
    
    public func stopDataCollection() {
        // 确保最后的缓冲数据被写入
        if !dataBuffer.isEmpty {
            let finalData = dataBuffer
            fileWriteQueue.async { [weak self] in
                guard let self = self else { return }
                
                for point in finalData {
                    let accString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                         point.timestamp,
                                         point.acc.x,
                                         point.acc.y,
                                         point.acc.z)
                    
                    let gyroString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                          point.timestamp,
                                          point.gyro.x,
                                          point.gyro.y,
                                          point.gyro.z)
                    
                    if let accData = accString.data(using: .utf8),
                       let gyroData = gyroString.data(using: .utf8) {
                        self.accFileHandle?.write(accData)
                        self.gyroFileHandle?.write(gyroData)
                    }
                }
                
                // 清理
                self.dataBuffer.removeAll()
                self.accFileHandle?.closeFile()
                self.accFileHandle = nil
                self.gyroFileHandle?.closeFile()
                self.gyroFileHandle = nil
            }
        }
        
        motionManager.stopDeviceMotionUpdates()
        isCollecting = false
        
        accelerationData = nil
        rotationData = nil
        
        WatchConnectivityManager.shared.resetState()
        
        // 关闭所有文件句柄
        peakFileHandle?.closeFile()
        peakFileHandle = nil
        valleyFileHandle?.closeFile()
        valleyFileHandle = nil
        selectedPeakFileHandle?.closeFile()
        selectedPeakFileHandle = nil
        quaternionFileHandle?.closeFile()
        quaternionFileHandle = nil
        
        // 关闭手势数据文件
        signalProcessor.closeFiles()
        print("Closed SignalProcessor files") // 添加调试信息
    }
    
    public var isGyroAvailable: Bool {
        return motionManager.isGyroAvailable
    }
    
    public func exportData() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            let dataFolders = fileURLs.filter { url in
                let folderName = url.lastPathComponent
                return (folderName.contains("_右手_") || folderName.contains("_左手_")) && 
                       url.hasDirectoryPath
            }
            
            if dataFolders.isEmpty {
                WatchConnectivityManager.shared.lastMessage = "没有数据可导出"
                return
            }
            
            WatchConnectivityManager.shared.sendDataToPhone(fileURLs: dataFolders)
        } catch {
            print("Error listing directory: \(error)")
            WatchConnectivityManager.shared.lastMessage = "导出失败: \(error.localizedDescription)"
        }
    }
    
    private func deleteAllData() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                if (fileURL.lastPathComponent.contains("_右手_") || fileURL.lastPathComponent.contains("_左手_")) &&
                   fileURL.hasDirectoryPath {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Error deleting all files: \(error)")
        }
    }
    
    private func savePeak(timestamp: UInt64, value: Double) {
        guard savePeaks else { return }
        let peakString = String(format: "%llu,%.6f\n", timestamp, value)
        if let data = peakString.data(using: .utf8) {
            peakFileHandle?.write(data)
        }
    }
    
    private func saveValley(timestamp: UInt64, value: Double) {
        guard saveValleys else { return }
        let valleyString = String(format: "%llu,%.6f\n", timestamp, value)
        if let data = valleyString.data(using: .utf8) {
            valleyFileHandle?.write(data)
        }
    }
    
    private func saveSelectedPeak(timestamp: UInt64, value: Double) {
        guard saveSelectedPeaks else { return }
        let selectedPeakString = String(format: "%llu,%.6f\n", timestamp, value)
        if let data = selectedPeakString.data(using: .utf8) {
            selectedPeakFileHandle?.write(data)
        }
    }
    
    private func saveQuaternion(timestamp: UInt64, quaternion: [Double]) {
        guard saveQuaternions else { return }
        let quaternionString = String(format: "%llu,%.6f,%.6f,%.6f,%.6f\n",
                                    timestamp,
                                    quaternion[0], // w
                                    quaternion[1], // x
                                    quaternion[2], // y
                                    quaternion[3]) // z
        if let data = quaternionString.data(using: .utf8) {
            quaternionFileHandle?.write(data)
        }
    }
    
    // 添加更新设置的方法
    public func updateSaveSettings(
        peaks: Bool? = nil,
        valleys: Bool? = nil,
        selectedPeaks: Bool? = nil,
        quaternions: Bool? = nil,
        gestureData: Bool? = nil
    ) {
        if let peaks = peaks {
            savePeaks = peaks
            UserDefaults.standard.set(peaks, forKey: "savePeaks")
        }
        if let valleys = valleys {
            saveValleys = valleys
            UserDefaults.standard.set(valleys, forKey: "saveValleys")
        }
        if let selectedPeaks = selectedPeaks {
            saveSelectedPeaks = selectedPeaks
            UserDefaults.standard.set(selectedPeaks, forKey: "saveSelectedPeaks")
        }
        if let quaternions = quaternions {
            saveQuaternions = quaternions
            UserDefaults.standard.set(quaternions, forKey: "saveQuaternions")
        }
        if let gestureData = gestureData {
            saveGestureData = gestureData
            UserDefaults.standard.set(gestureData, forKey: "saveGestureData")
            print("MotionManager: Updating gesture data saving to \(gestureData)")
            // 立即更新 GestureRecognizer 的设置
            signalProcessor.gestureRecognizer.updateSettings(saveGestureData: gestureData)
        }
    }
}
#endif
