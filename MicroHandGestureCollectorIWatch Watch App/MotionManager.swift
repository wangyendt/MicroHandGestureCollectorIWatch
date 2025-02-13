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
    
    // 添加定时器相关属性
    private var reminderTimer: Timer?
    private var lastTapTime: Date = Date()
    private var hasShownReminder: Bool = false
    
    private let modelMap: [String: (deviceType: String, size: String, variant: String, chipset: String, modelNumber: String)] = [
        
        // https://theapplewiki.com/wiki/List_of_Apple_Watches 
        // https://support.apple.com/zh-cn/108056
        
        // Apple Watch Series 10
        "Watch7,8_NA": ("Apple Watch Series 10", "42mm", "GPS", "S10", "A2997"), // 北美洲
        "Watch7,8_EU": ("Apple Watch Series 10", "42mm", "GPS", "S10", "A2997"), // 欧洲、亚太地区
        "Watch7,8_CN": ("Apple Watch Series 10", "42mm", "GPS", "S10", "A2998"), // 中国大陆
        
        "Watch7,9_NA": ("Apple Watch Series 10", "46mm", "GPS", "S10", "A2999"), // 北美洲
        "Watch7,9_EU": ("Apple Watch Series 10", "46mm", "GPS", "S10", "A2999"), // 欧洲、亚太地区
        "Watch7,9_CN": ("Apple Watch Series 10", "46mm", "GPS", "S10", "A3000"), // 中国大陆
        
        "Watch7,10_NA": ("Apple Watch Series 10", "42mm", "GPS+Cellular", "S10", "A3001"), // 北美洲
        "Watch7,10_EU": ("Apple Watch Series 10", "42mm", "GPS+Cellular", "S10", "A3001"), // 欧洲、亚太地区
        "Watch7,10_CN": ("Apple Watch Series 10", "42mm", "GPS+Cellular", "S10", "A3002"), // 中国大陆
        
        "Watch7,11_NA": ("Apple Watch Series 10", "46mm", "GPS+Cellular", "S10", "A3003"), // 北美洲
        "Watch7,11_EU": ("Apple Watch Series 10", "46mm", "GPS+Cellular", "S10", "A3003"), // 欧洲、亚太地区
        "Watch7,11_CN": ("Apple Watch Series 10", "46mm", "GPS+Cellular", "S10", "A3006"), // 中国大陆

        // Apple Watch Ultra 2
        "Watch7,5_NA": ("Apple Watch Ultra 2", "49mm", "GPS+Cellular", "S9", "A2986"), // 北美洲
        "Watch7,5_EU": ("Apple Watch Ultra 2", "49mm", "GPS+Cellular", "S9", "A2986"), // 欧洲、亚太地区
        "Watch7,5_CN": ("Apple Watch Ultra 2", "49mm", "GPS+Cellular", "S9", "A2987"), // 中国大陆

        // Apple Watch Series 9
        "Watch7,1": ("Apple Watch Series 9", "41mm", "GPS", "S9", "A2978"),
        "Watch7,2": ("Apple Watch Series 9", "45mm", "GPS", "S9", "A2980"),
        
        "Watch7,3_NA": ("Apple Watch Series 9", "41mm", "GPS+Cellular", "S9", "A2982"), // 北美洲
        "Watch7,3_EU": ("Apple Watch Series 9", "41mm", "GPS+Cellular", "S9", "A2982"), // 欧洲、亚太地区
        "Watch7,3_CN": ("Apple Watch Series 9", "41mm", "GPS+Cellular", "S9", "A2983"), // 中国大陆
        
        "Watch7,4_NA": ("Apple Watch Series 9", "45mm", "GPS+Cellular", "S9", "A2984"), // 北美洲
        "Watch7,4_EU": ("Apple Watch Series 9", "45mm", "GPS+Cellular", "S9", "A2984"), // 欧洲、亚太地区
        "Watch7,4_CN": ("Apple Watch Series 9", "45mm", "GPS+Cellular", "S9", "A2985"), // 中国大陆

        // Apple Watch Series 8
        "Watch6,14": ("Apple Watch Series 8", "41mm", "GPS", "S8", "A2770"),
        "Watch6,15": ("Apple Watch Series 8", "45mm", "GPS", "S8", "A2771"),
        
        "Watch6,16_NA": ("Apple Watch Series 8", "41mm", "GPS+Cellular", "S8", "A2772"), // 北美洲
        "Watch6,16_EU": ("Apple Watch Series 8", "41mm", "GPS+Cellular", "S8", "A2773"), // 欧洲、亚太地区
        "Watch6,16_CN": ("Apple Watch Series 8", "41mm", "GPS+Cellular", "S8", "A2857"), // 中国大陆
        
        "Watch6,17_NA": ("Apple Watch Series 8", "45mm", "GPS+Cellular", "S8", "A2774"), // 北美洲
        "Watch6,17_EU": ("Apple Watch Series 8", "45mm", "GPS+Cellular", "S8", "A2775"), // 欧洲、亚太地区
        "Watch6,17_CN": ("Apple Watch Series 8", "45mm", "GPS+Cellular", "S8", "A2858"), // 中国大陆

        // Apple Watch SE (2nd generation)
        "Watch6,10": ("Apple Watch SE 2", "40mm", "GPS", "S8", "A2722"),
        "Watch6,11": ("Apple Watch SE 2", "44mm", "GPS", "S8", "A2723"),
        
        "Watch6,12_NA": ("Apple Watch SE 2", "40mm", "GPS+Cellular", "S8", "A2726"), // 北美洲
        "Watch6,12_EU": ("Apple Watch SE 2", "40mm", "GPS+Cellular", "S8", "A2725"), // 欧洲、亚太地区
        "Watch6,12_CN": ("Apple Watch SE 2", "40mm", "GPS+Cellular", "S8", "A2855"), // 中国大陆
        
        "Watch6,13_NA": ("Apple Watch SE 2", "44mm", "GPS+Cellular", "S8", "A2727"), // 北美洲
        "Watch6,13_EU": ("Apple Watch SE 2", "44mm", "GPS+Cellular", "S8", "A2724"), // 欧洲、亚太地区
        "Watch6,13_CN": ("Apple Watch SE 2", "44mm", "GPS+Cellular", "S8", "A2856"), // 中国大陆

        // Apple Watch Series 7
        "Watch6,6": ("Apple Watch Series 7", "41mm", "GPS", "S7", "A2473"),
        "Watch6,7": ("Apple Watch Series 7", "45mm", "GPS", "S7", "A2474"),
        
        "Watch6,8_NA": ("Apple Watch Series 7", "41mm", "GPS+Cellular", "S7", "A2475"), // 北美洲
        "Watch6,8_EU": ("Apple Watch Series 7", "41mm", "GPS+Cellular", "S7", "A2476"), // 欧洲、亚太地区
        "Watch6,8_CN": ("Apple Watch Series 7", "41mm", "GPS+Cellular", "S7", "A2476"), // 中国大陆
        
        "Watch6,9_NA": ("Apple Watch Series 7", "45mm", "GPS+Cellular", "S7", "A2477"), // 北美洲
        "Watch6,9_EU": ("Apple Watch Series 7", "45mm", "GPS+Cellular", "S7", "A2478"), // 欧洲、亚太地区
        "Watch6,9_CN": ("Apple Watch Series 7", "45mm", "GPS+Cellular", "S7", "A2478"), // 中国大陆

        // Apple Watch Series 6
        "Watch6,1": ("Apple Watch Series 6", "40mm", "GPS", "S6", "A2291"),
        "Watch6,2": ("Apple Watch Series 6", "44mm", "GPS", "S6", "A2292"),
        
        "Watch6,3_NA": ("Apple Watch Series 6", "40mm", "GPS+Cellular", "S6", "A2293"), // 北美洲
        "Watch6,3_EU": ("Apple Watch Series 6", "40mm", "GPS+Cellular", "S6", "A2375"), // 欧洲、亚太地区
        "Watch6,3_CN": ("Apple Watch Series 6", "40mm", "GPS+Cellular", "S6", "A2375"), // 中国大陆
        
        "Watch6,4_NA": ("Apple Watch Series 6", "44mm", "GPS+Cellular", "S6", "A2294"), // 北美洲
        "Watch6,4_EU": ("Apple Watch Series 6", "44mm", "GPS+Cellular", "S6", "A2376"), // 欧洲、亚太地区
        "Watch6,4_CN": ("Apple Watch Series 6", "44mm", "GPS+Cellular", "S6", "A2376"), // 中国大陆

        // Apple Watch Series 5
        "Watch5,1": ("Apple Watch Series 5", "40mm", "GPS", "S5", "A2092"),
        "Watch5,2": ("Apple Watch Series 5", "44mm", "GPS", "S5", "A2093"),
        
        "Watch5,3_NA": ("Apple Watch Series 5", "40mm", "GPS+Cellular", "S5", "A2094"), // 北美洲
        "Watch5,3_EU": ("Apple Watch Series 5", "40mm", "GPS+Cellular", "S5", "A2156"), // 欧洲、亚太地区
        "Watch5,3_CN": ("Apple Watch Series 5", "40mm", "GPS+Cellular", "S5", "A2156"), // 中国大陆
        
        "Watch5,4_NA": ("Apple Watch Series 5", "44mm", "GPS+Cellular", "S5", "A2095"), // 北美洲
        "Watch5,4_EU": ("Apple Watch Series 5", "44mm", "GPS+Cellular", "S5", "A2157"), // 欧洲、亚太地区
        "Watch5,4_CN": ("Apple Watch Series 5", "44mm", "GPS+Cellular", "S5", "A2157"), // 中国大陆

        // Apple Watch Series 4
        "Watch4,1": ("Apple Watch Series 4", "40mm", "GPS", "S4", "A1977"),
        "Watch4,2": ("Apple Watch Series 4", "44mm", "GPS", "S4", "A1978"),
        
        "Watch4,3_NA": ("Apple Watch Series 4", "40mm", "GPS+Cellular", "S4", "A1975"), // 北美洲
        "Watch4,3_EU": ("Apple Watch Series 4", "40mm", "GPS+Cellular", "S4", "A2007"), // 欧洲、亚太地区
        "Watch4,3_CN": ("Apple Watch Series 4", "40mm", "GPS+Cellular", "S4", "A2007"), // 中国大陆
        
        "Watch4,4_NA": ("Apple Watch Series 4", "44mm", "GPS+Cellular", "S4", "A1976"), // 北美洲
        "Watch4,4_EU": ("Apple Watch Series 4", "44mm", "GPS+Cellular", "S4", "A2008"), // 欧洲、亚太地区
        "Watch4,4_CN": ("Apple Watch Series 4", "44mm", "GPS+Cellular", "S4", "A2008"), // 中国大陆

        // Apple Watch Series 3
        "Watch3,1_NA": ("Apple Watch Series 3", "38mm", "GPS+Cellular", "S3", "A1860"), // 美洲
        "Watch3,1_EU": ("Apple Watch Series 3", "38mm", "GPS+Cellular", "S3", "A1889"), // 欧洲和亚太地区
        "Watch3,1_CN": ("Apple Watch Series 3", "38mm", "GPS+Cellular", "S3", "A1890"), // 中国大陆
        
        "Watch3,2_NA": ("Apple Watch Series 3", "42mm", "GPS+Cellular", "S3", "A1861"), // 美洲
        "Watch3,2_EU": ("Apple Watch Series 3", "42mm", "GPS+Cellular", "S3", "A1891"), // 欧洲和亚太地区
        "Watch3,2_CN": ("Apple Watch Series 3", "42mm", "GPS+Cellular", "S3", "A1892"), // 中国大陆
        
        "Watch3,3": ("Apple Watch Series 3", "38mm", "GPS", "S3", "A1858"),
        "Watch3,4": ("Apple Watch Series 3", "42mm", "GPS", "S3", "A1859"),

        // Apple Watch Series 2
        "Watch2,3": ("Apple Watch Series 2", "38mm", "GPS", "S2", "A1757"),
        "Watch2,4": ("Apple Watch Series 2", "42mm", "GPS", "S2", "A1758"),

        // Apple Watch Series 1
        "Watch2,6": ("Apple Watch Series 1", "38mm", "GPS", "S1P", "A1802"),
        "Watch2,7": ("Apple Watch Series 1", "42mm", "GPS", "S1P", "A1803"),

        // Apple Watch (1st generation)
        "Watch1,1": ("Apple Watch", "38mm", "GPS", "S1", "A1553"),
        "Watch1,2": ("Apple Watch", "42mm", "GPS", "S1", "A1554")
    ]
    
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
        // 峰值反馈
        FeedbackManager.playFeedback(
            style: .success,
            withFlash: true,
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
        // 手势反馈
        FeedbackManager.playFeedback(
            style: .success,
            withFlash: true,
            speak: "\(gesture)"
        )
        print("识别到手势: \(gesture), 置信度: \(confidence)")
    }
    
    public func startDataCollection(
        name: String,
        hand: String,
        gesture: String,
        force: String,
        gender: String,
        tightness: String,
        note: String,
        wristSize: String,
        bandType: String
    ) {
        // 重置计数器
        signalProcessor.resetCount()  // 重置计数
        signalProcessor.resetStartTime()  // 重置开始时间
        peakCount = 0
        
        // 重置最后点击时间为当前时间
        lastTapTime = Date()
        hasShownReminder = false
        
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
            
            // 保存设备信息
            saveDeviceInfo(
                to: folderURL,
                name: name,
                hand: hand,
                gesture: gesture,
                force: force,
                gender: gender,
                tightness: tightness,
                note: note,
                wristSize: wristSize,
                bandType: bandType
            )
            
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
        
        WatchConnectivityManager.shared.setCurrentFolder(folderURL)  // 设置当前文件夹
        
        // 启动提醒定时器
        startReminderTimer()
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
        
        signalProcessor.resetStartTime()  // 重置开始时间
        
        // 停止提醒定时器
        stopReminderTimer()
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
        gestureData: Bool? = nil,
        resultFile: Bool? = nil
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
        if let resultFile = resultFile {
            signalProcessor.updateSettings(saveResult: resultFile)
        }
    }
    
    // 在 MotionManager 类中添加新的方法
    private func saveDeviceInfo(
        to folderURL: URL,
        name: String,
        hand: String,
        gesture: String,
        force: String,
        gender: String,
        tightness: String,
        note: String,
        wristSize: String,
        bandType: String
    ) {
        var info = collectDeviceInfo()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        info["collection_time"] = dateFormatter.string(from: Date())
        info["participant_name"] = name
        info["hand"] = hand
        info["gesture"] = gesture
        info["force"] = force
        info["gender"] = gender
        info["tightness"] = tightness
        info["note"] = note
        info["wrist_size"] = wristSize
        info["band_type"] = bandType
        
        let infoFileURL = folderURL.appendingPathComponent("info.yaml")
        
        do {
            let yamlString = generateYAMLString(from: info)
            try yamlString.write(to: infoFileURL, atomically: true, encoding: .utf8)
            print("成功保存信息到: \(infoFileURL.path)")
        } catch {
            print("保存信息失败: \(error)")
        }
    }
    
    private func collectDeviceInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        // 获取设备型号
        let device = WKInterfaceDevice.current()
        info["model"] = device.model                    // 例如: "Apple Watch"
        info["systemVersion"] = device.systemVersion    // 例如: "10.0"
        
        // 获取详细的设备型号标识符
        var sysinfo = utsname()
        uname(&sysinfo)
        let modelCode = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String(validatingUTF8: ptr)
            }
        } ?? "unknown"
        info["modelIdentifier"] = modelCode   // 例如: "Watch6,1" 表示 Apple Watch Series 6 40mm
        
        // 解析具体的设备型号信息
        let detailedModel = parseModelIdentifier(modelCode)
        info["deviceType"] = detailedModel.deviceType       // 例如: "Apple Watch Series 7"
        info["deviceSize"] = detailedModel.size            // 例如: "45mm" 或 "41mm"
        info["deviceVariant"] = detailedModel.variant      // 例如: "GPS" 或 "GPS+Cellular"
        info["chipset"] = detailedModel.chipset           // 例如: "S7" 或 "S8"
        info["modelNumber"] = detailedModel.modelNumber    // 例如: "A2478"
        
        // 获取屏幕尺寸信息
        let screenSize = device.screenBounds
        info["screenWidth"] = "\(screenSize.width)"
        info["screenHeight"] = "\(screenSize.height)"
        
        // 获取设备名称
        info["name"] = device.name
        
        // 获取设备标识符
        info["identifierForVendor"] = device.identifierForVendor?.uuidString ?? "unknown"
        
        // 获取电池状态
        // info["batteryState"] = "\(device.batteryState.rawValue)"
        // info["batteryLevel"] = "\(device.batteryLevel)"
        
        // 获取设备容量信息
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let totalSize = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            let freeSize = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            info["totalDiskSpace"] = "\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
            info["freeDiskSpace"] = "\(ByteCountFormatter.string(fromByteCount: freeSize, countStyle: .file))"
        }
        
        // 获取传感器采样率信息
//        info["accelerometerUpdateInterval"] = "\(motionManager.accelerometerUpdateInterval)"
//        info["gyroUpdateInterval"] = "\(motionManager.gyroUpdateInterval)"
        
        // 获取传感器可用性信息
//        info["isAccelerometerAvailable"] = "\(motionManager.isAccelerometerAvailable)"
//        info["isGyroAvailable"] = "\(motionManager.isGyroAvailable)"
//        info["isDeviceMotionAvailable"] = "\(motionManager.isDeviceMotionAvailable)"
        
        return info
    }
    
    private func generateYAMLString(from info: [String: String]) -> String {
        var yamlString = "# 采集信息\n"
        yamlString += "collection:\n"
        yamlString += "  time: \(info["collection_time"] ?? "")\n"
        yamlString += "  participant_name: \(info["participant_name"] ?? "")\n"
        yamlString += "  hand: \(info["hand"] ?? "")\n"
        yamlString += "  gesture: \(info["gesture"] ?? "")\n"
        yamlString += "  force: \(info["force"] ?? "")\n"
        yamlString += "  gender: \(info["gender"] ?? "")\n"
        yamlString += "  tightness: \(info["tightness"] ?? "")\n"
        yamlString += "  wrist_size: \(info["wrist_size"] ?? "")\n"
        yamlString += "  band_type: \(info["band_type"] ?? "")\n"
        yamlString += "  note: \(info["note"] ?? "")\n\n"
        
        yamlString += "# 设备信息\n"
        yamlString += "device:\n"
        for key in info.keys.sorted() where !["collection_time", "participant_name", "hand", "gesture", "force", "gender", "tightness", "note", "wrist_size", "band_type"].contains(key) {
            if let value = info[key] {
                yamlString += "  \(key): \(value)\n"
            }
        }
        
        return yamlString
    }
    
    private func parseModelIdentifier(_ identifier: String) -> (deviceType: String, size: String, variant: String, chipset: String, modelNumber: String) {
        // 获取区域信息
        let region = determineDeviceRegion()
        
        // 构造完整的标识符（包含区域信息）
        let fullIdentifier = "\(identifier)_\(region)"
        
        print("Debug Info:")
        print("- Base Identifier: \(identifier)")
        print("- Region: \(region)")
        print("- Full Identifier: \(fullIdentifier)")
        
        // 使用完整标识符查找匹配
        if let model = modelMap[fullIdentifier] {
            print("Found match with region")
            return model
        }
        
        // 如果找不到带区域的匹配，尝试使用基础标识符
        if let model = modelMap[identifier] {
            print("Found match without region")
            return model
        }
        
        print("No matching model found")
        return (
            deviceType: "Unknown (\(identifier))",
            size: "Unknown",
            variant: "Unknown",
            chipset: "Unknown",
            modelNumber: "Unknown"
        )
    }
    
    private func determineDeviceRegion() -> String {
        // 获取当前区域设置
        let locale = Locale.current
        let regionCode = locale.region?.identifier.uppercased() ?? ""
        
        // 北美地区
        let northAmericaRegions = ["US", "CA", "MX"]
        if northAmericaRegions.contains(regionCode) {
            return "NA"
        }
        
        // 中国大陆
        if regionCode == "CN" {
            return "CN"
        }
        
        // 其他地区都归类为欧洲和亚太地区
        return "EU"
    }
    
    // 添加定时器管理方法
    private func startReminderTimer() {
        // 停止现有定时器
        stopReminderTimer()
        
        // 重置提醒状态
        hasShownReminder = false
        
        print("开始设置提醒定时器")
        
        // 创建新定时器，每1秒触发一次检查
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 检查距离上次点击是否已经过去10秒
            let timeSinceLastTap = Date().timeIntervalSince(self.lastTapTime)
            print("距离上次点击已经过去: \(String(format: "%.1f", timeSinceLastTap))秒")
            
            if timeSinceLastTap >= 60.0 && !self.hasShownReminder {
                print("触发提醒：已超过60秒未操作")
                // 使用 FeedbackManager 播放语音提示
                FeedbackManager.playFeedback(
                    style: .notification,
                    withFlash: false,
                    speak: "滑动手表屏幕",
                    forceSpeak: true  // 强制播报
                )
                self.hasShownReminder = true
                // 重置最后点击时间，开始新的10秒计时
                self.lastTapTime = Date()
                // 重置提醒状态，这样下一个10秒周期可以继续提醒
                self.hasShownReminder = false
            }
        }
        
        print("提醒定时器设置完成")
    }
    
    private func stopReminderTimer() {
        if reminderTimer != nil {
            print("停止提醒定时器")
            reminderTimer?.invalidate()
            reminderTimer = nil
        }
    }
    
    // 添加更新最后点击时间的方法
    public func updateLastTapTime() {
        lastTapTime = Date()
        hasShownReminder = false
        print("更新最后点击时间: \(lastTapTime)")
    }
}
#endif
