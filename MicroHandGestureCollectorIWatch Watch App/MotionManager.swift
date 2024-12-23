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
    private var isCollecting = false
    private var logger: OSLog
    
    @Published var isReady = true
    
    private var runtimeSession: WKExtendedRuntimeSession?
    
    // 添加文件写入队列
    private let fileWriteQueue = DispatchQueue(label: "com.wayne.fileWriteQueue", qos: .utility)
    
    // 添加数据缓冲区
    private var dataBuffer: [(timestamp: UInt64, acc: (x: Double, y: Double, z: Double), gyro: (x: Double, y: Double, z: Double))] = []
    private let bufferSize = 10 // 每10个数据点写入一次文件
    
    private let signalProcessor = SignalProcessor()
    
    public init() {
        logger = OSLog(subsystem: "wayne.MicroHandGestureCollectorIWatch.watchkitapp", category: "sensors")

        motionManager = CMMotionManager()
        print("MotionManager 初始化")
        print("加速度计状态: \(motionManager.isAccelerometerAvailable ? "可用" : "不可用")")
        print("陀螺仪状态: \(motionManager.isGyroAvailable ? "可用" : "不可用")")
        print("设备运动状态: \(motionManager.isDeviceMotionAvailable ? "可用" : "不可用")")
        
        // 设置代理
        signalProcessor.delegate = self
    }
    
    // 实现代理方法
    func signalProcessor(_ processor: SignalProcessor, didDetectStrongPeak value: Double) {
        // 触发振动和视觉反馈
        FeedbackManager.playFeedback(style: .success)
    }
    
    public func startDataCollection(name: String, hand: String, gesture: String, force: String, note: String) {
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
            
            // 创建文件
            let accFileURL = folderURL.appendingPathComponent("acc.txt")
            let gyroFileURL = folderURL.appendingPathComponent("gyro.txt")
            
            // 创建文件头部信息
//            let headerInfo = "采集时间: \(Date())\n姓名: \(name)\n手: \(hand)\n手势: \(gesture)\n力度: \(force)\n备注: \(note)\n---\n"
            let accHeader = "timestamp_ns,acc_x,acc_y,acc_z\n"
            let gyroHeader = "timestamp_ns,gyro_x,gyro_y,gyro_z\n"
            
            // 写入文件头部信息
            try (accHeader).write(to: accFileURL, atomically: true, encoding: .utf8)
            try (gyroHeader).write(to: gyroFileURL, atomically: true, encoding: .utf8)
            
            accFileHandle = try FileHandle(forWritingTo: accFileURL)
            gyroFileHandle = try FileHandle(forWritingTo: gyroFileURL)
            
            // 移动到文件末尾
            accFileHandle?.seekToEndOfFile()
            gyroFileHandle?.seekToEndOfFile()
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

            // 处理新的数据点
            self?.signalProcessor.processNewPoint(
                timestamp: motion.timestamp,
                accNorm: accNorm
            )

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
                self?.signalProcessor.printStatus()
                printCounter = 0
            }
        }
        
        isCollecting = true
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
        
        runtimeSession?.invalidate()
        runtimeSession = nil
        
        motionManager.stopDeviceMotionUpdates()
        isCollecting = false
        
        accelerationData = nil
        rotationData = nil
        
        WatchConnectivityManager.shared.resetState()
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
}
#endif
