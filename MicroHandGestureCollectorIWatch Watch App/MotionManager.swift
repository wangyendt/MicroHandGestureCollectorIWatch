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
public class MotionManager: ObservableObject {
    @Published private(set) var accelerationData: CMAcceleration?
    @Published private(set) var rotationData: CMRotationRate?
    private let motionManager: CMMotionManager
    private var accFileHandle: FileHandle?
    private var gyroFileHandle: FileHandle?
    private var isCollecting = false
    private var logger: OSLog
    
    @Published var isReady = true
    
    private var runtimeSession: WKExtendedRuntimeSession?
    
    public init() {
        logger = OSLog(subsystem: "wayne.MicroHandGestureCollectorIWatch.watchkitapp", category: "sensors")

        motionManager = CMMotionManager()
        print("MotionManager 初始化")
        print("加速度计状态: \(motionManager.isAccelerometerAvailable ? "可用" : "不可用")")
        print("陀螺仪状态: \(motionManager.isGyroAvailable ? "可用" : "不可用")")
        print("设备运动状态: \(motionManager.isDeviceMotionAvailable ? "可用" : "不可用")")
    }
    
    public func startDataCollection(hand: String, gesture: String, force: String, note: String) {
        stopDataCollection()
        isCollecting = true
        
        runtimeSession = WKExtendedRuntimeSession()
        runtimeSession?.start()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        let timestamp = dateFormatter.string(from: Date())
        let folderName = "\(timestamp)_\(hand)_\(gesture)_\(force)_\(note)"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法访问文档目录")
            return
        }
        
        let folderURL = documentsPath.appendingPathComponent(folderName)
        let accFileURL = folderURL.appendingPathComponent("acc.txt")
        let gyroFileURL = folderURL.appendingPathComponent("gyro.txt")
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            
            FileManager.default.createFile(atPath: accFileURL.path, contents: nil)
            FileManager.default.createFile(atPath: gyroFileURL.path, contents: nil)
            accFileHandle = try FileHandle(forWritingTo: accFileURL)
            gyroFileHandle = try FileHandle(forWritingTo: gyroFileURL)
            
            let accHeader = "timestamp_ns,acc_x,acc_y,acc_z\n"
            let gyroHeader = "timestamp_ns,gyro_x,gyro_y,gyro_z\n"
            accFileHandle?.write(accHeader.data(using: .utf8)!)
            gyroFileHandle?.write(gyroHeader.data(using: .utf8)!)
            
            motionManager.deviceMotionUpdateInterval = 1.0 / 200.0
            
            if motionManager.isDeviceMotionAvailable {
                let queue = OperationQueue()
                queue.qualityOfService = .userInitiated
                
                motionManager.startDeviceMotionUpdates(to: queue) { [weak self] (motion, error) in
                    guard let self = self, let motion = motion else { return }
                    
                    DispatchQueue.main.async {
                        let timestampNs = UInt64(motion.timestamp * 1_000_000_000)
                        
                        let totalAccX = motion.gravity.x * 9.81 + motion.userAcceleration.x * 9.81
                        let totalAccY = motion.gravity.y * 9.81 + motion.userAcceleration.y * 9.81
                        let totalAccZ = motion.gravity.z * 9.81 + motion.userAcceleration.z * 9.81
                        os_log("timestampNs: %lld, totalAccX: %.6f, totalAccY: %.6f, totalAccZ: %.6f",
                               log: self.logger,
                               type: .debug,
                               timestampNs,
                               totalAccX,
                               totalAccY,
                               totalAccZ)
                        
                        let accDataString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                                timestampNs,
                                                totalAccX,
                                                totalAccY,
                                                totalAccZ)
                        
                        let gyroDataString = String(format: "%llu,%.6f,%.6f,%.6f\n",
                                                 timestampNs,
                                                 motion.rotationRate.x,
                                                 motion.rotationRate.y,
                                                 motion.rotationRate.z)
                        
                        if let accData = accDataString.data(using: .utf8),
                           let gyroData = gyroDataString.data(using: .utf8) {
                            self.accFileHandle?.write(accData)
                            self.gyroFileHandle?.write(gyroData)
                        }
                        
                        let totalAcc = CMAcceleration(x: totalAccX, y: totalAccY, z: totalAccZ)
                        self.accelerationData = totalAcc
                        self.rotationData = motion.rotationRate
                        
                        WatchConnectivityManager.shared.sendRealtimeData(
                            accData: totalAcc,
                            gyroData: motion.rotationRate,
                            timestamp: timestampNs
                        )
                    }
                }
            } else {
                print("设备运动数据不可用")
            }
        } catch {
            print("创建文件失败: \(error)")
            return
        }
    }
    
    public func stopDataCollection() {
        runtimeSession?.invalidate()
        runtimeSession = nil
        
        motionManager.stopDeviceMotionUpdates()
        accFileHandle?.closeFile()
        accFileHandle = nil
        gyroFileHandle?.closeFile()
        gyroFileHandle = nil
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
            let dataFiles = fileURLs.filter { url in
                let filename = url.lastPathComponent
                return filename.contains("_右手_") || filename.contains("_左手_")
            }
            
            if dataFiles.isEmpty {
                print("No data files to export")
                return
            }
            
            WatchConnectivityManager.shared.sendDataToPhone(fileURLs: dataFiles)
            
        } catch {
            print("Error exporting files: \(error)")
        }
    }
}
#endif
