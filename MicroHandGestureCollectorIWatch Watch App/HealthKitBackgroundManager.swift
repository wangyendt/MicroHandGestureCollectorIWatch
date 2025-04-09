//
//  HealthKitManager.swift
//  DrStarriseWorld
//
//  Created by daoran on 2025/3/26.
//

import HealthKit
import WatchKit

class HealthKitBackgroundManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    private var backgroundSessionManager = BackgroundSessionManager()

    override init() {
        super.init()
        requestAuthorization()
    }

    // 请求 HealthKit 权限
    private func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit 不可用")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]
        
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType() // 需要写入权限，才能使用 HKWorkoutSession
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            if success {
                print("✅ HealthKit 授权成功")
            } else {
                print("❌ HealthKit 授权失败: \(error?.localizedDescription ?? "未知错误")")
            }
        }
    }

    // 启动 WorkoutSession 采集心率 & 卡路里
    func startWorkoutSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            
            session?.delegate = self
            builder?.delegate = self
            
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            session?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { success, error in
                if success {
                    print("✅ HealthKit 采集启动成功")
                    
                    // ✅ Workout 启动后再开启 WKExtendedRuntimeSession
                    self.startExtendedSession()
                    
                } else {
                    print("❌ HealthKit 采集启动失败: \(error?.localizedDescription ?? "未知错误")")
                }
            }
        } catch {
            print("❌ 无法启动 WorkoutSession: \(error.localizedDescription)")
        }
    }

    func startExtendedSession() {
        backgroundSessionManager.startExtendedSession()
    }
    
    // 停止扩展会话
    func stopExtendedSession() {
        backgroundSessionManager.stopExtendedSession()
        print("✅ 扩展会话已停止")
    }
    
    // 停止 WorkoutSession
    func stopWorkoutSession() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { success, error in
            if success {
                print("✅ HealthKit 采集已停止")
                
                // 停止扩展会话
                self.stopExtendedSession()
            } else {
                print("❌ 停止采集失败: \(error?.localizedDescription ?? "未知错误")")
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        // 输出错误信息
        print("🚨 运动会话失败，错误: \(error.localizedDescription)")
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // 遍历每个收集到的数据类型
        for type in collectedTypes {
            if let quantityType = type as? HKQuantityType {
                print("收集到数据类型: \(quantityType.identifier)")  // 打印采集到的数据类型
                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    processStatistics(statistics, type: quantityType)
                }
            }
        }
    }

    // 处理心率 & 卡路里数据
    private func processStatistics(_ statistics: HKStatistics, type: HKQuantityType) {
        if type == HKQuantityType.quantityType(forIdentifier: .heartRate) {
            if let heartRate = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                print("❤️ 心率: \(heartRate) BPM")
            } else {
                print("❌ 无法获取心率数据")
            }
        }

        if type == HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            if let energyBurned = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.kilocalorie()) {
                print("🔥 卡路里: \(energyBurned) kcal")
            }
        }
    }

    // 必须实现的方法：监听 Workout 事件
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        print("📌 HealthKit 收到 Workout 事件")
    }

    // 状态改变通知
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        switch toState {
        case .running:
            print("🏃‍♂️ WorkoutSession 运行中")
        case .ended:
            print("🛑 WorkoutSession 已结束")
        default:
            break
        }
    }
}

