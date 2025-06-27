import WatchKit
import SwiftUI // Needed for WKApplicationDelegateAdaptor

class AppDelegate: NSObject, WKApplicationDelegate {
    // Remove CommunicationManager dependency
    // let communicationManager = CommunicationManager.shared
    
    // Use lazy var with the correct MotionManager initializer
    // private lazy var motionManager = MotionManager() // Assume MotionManager() takes no arguments
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
        // communicationManager.startCommunication() // Remove direct call
        // WatchConnectivityManager.shared.activateSession() // Remove this call, activation handled internally
        // motionManager.startSensorUpdates() // Remove this call, start sensors via UI
        healthKitManager.startWorkoutSession() // This will check/request auth and keep app running
        
        // 初始化蓝牙服务（不自动扫描）
        _ = BleCentralService.shared
        print("📱 AppDelegate: 蓝牙服务已初始化")
    }

    // 应用进入后台时调用
    func applicationWillResignActive() {
        print("应用即将进入后台 (Resign Active)")
        // Stop services that shouldn't run in background without extended session
        // Note: HK session continues due to extended runtime session started by HealthKitManager
        // communicationManager.stopCommunication() // Remove direct call
        // motionManager.stopDataCollection() // Remove this, HK session should keep sensors running
    }

    // 应用进入后台时调用 (Deprecated, use applicationWillResignActive)
    // func applicationDidEnterBackground() { ... }

    // 应用终止时调用
    func applicationWillTerminate() {
        print("应用即将终止")
        // Ensure everything is stopped cleanly
        // communicationManager.stopCommunication() // Remove direct call
        // motionManager.stopDataCollection() // Use the correct stop method name
        healthKitManager.stopWorkoutSession() // This also stops the extended session
    }
    
    // Removed the commented-out extension for activateSession
}

// Add activateSession method to WatchConnectivityManager if it doesn't exist
// Or ensure it's called appropriately elsewhere.
// Example extension (place this in WatchConnectivityManager.swift or keep AppDelegate simpler):
/*
extension WatchConnectivityManager {
    func activateSession() {
        if WCSession.isSupported() && WCSession.default.activationState != .activated {
            WCSession.default.delegate = self // Ensure delegate is set
            WCSession.default.activate()
            print("WCSession activated from AppDelegate")
        }
    }
}
*/ 
