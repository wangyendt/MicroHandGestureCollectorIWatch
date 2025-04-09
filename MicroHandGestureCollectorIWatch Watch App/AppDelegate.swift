import WatchKit
import SwiftUI // Needed for WKApplicationDelegateAdaptor

class AppDelegate: NSObject, WKApplicationDelegate {
    let communicationManager = CommunicationManager.shared
    // Use lazy var to ensure CommunicationManager is initialized first if needed
    private lazy var motionManager = MotionManager(communicationManager: communicationManager)
    private lazy var healthKitManager = HealthKitBackgroundManager()

    // App launched
    func applicationDidFinishLaunching() {
        print("🚀 应用已启动")
        // Request HK authorization early if appropriate, or wait for user action
        // healthKitManager.requestAuthorization { _ in }
    }

    // 应用回到前台时调用
    func applicationDidBecomeActive() {
        print("应用回到前台")
        // Start services when app becomes active
        communicationManager.startCommunication()
        motionManager.startSensorUpdates()
        healthKitManager.startWorkoutSession() // This will check/request auth if needed
    }

    // 应用进入后台时调用
    func applicationWillResignActive() {
        print("应用即将进入后台 (Resign Active)")
        // Stop services that shouldn't run in background without extended session
        // Note: HK session continues due to extended runtime session started by HealthKitManager
        // communicationManager.stopCommunication() // Decide if comms should stop
        // motionManager.stopSensorUpdates() // Decide if motion should stop
    }

    // 应用进入后台时调用 (Deprecated, use applicationWillResignActive)
    // func applicationDidEnterBackground() { ... }

    // 应用终止时调用
    func applicationWillTerminate() {
        print("应用即将终止")
        // Ensure everything is stopped cleanly
        communicationManager.stopCommunication()
        motionManager.stopSensorUpdates()
        healthKitManager.stopWorkoutSession() // This also stops the extended session
    }
} 