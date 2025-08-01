//
//  MicroHandGestureCollectorWatchOSApp.swift
//  MicroHandGestureCollectorWatchOS Watch App
//
//  Created by wayne on 2024/11/13.
//

import SwiftUI
import WatchKit

@main
struct MicroHandGestureCollectorIWatch_Watch_AppApp: App {
    // 添加 AppDelegate 作为委托
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 初始化蓝牙服务单例
    private let bleService = BleCentralService.shared
    
    init() {
        print("📱 应用初始化")
        
        // 注册默认设置
        registerDefaultsSettings()
        
        // 初始化反馈管理器
        FeedbackManager.initialize()
    }
    
    private func registerDefaultsSettings() {
        let defaults: [String: Any] = [
            "peakThreshold": 0.3,
            "peakWindow": 0.2,
            "gestureCooldownWindow": 0.5,
            "savePeaks": false,
            "saveValleys": false,
            "saveSelectedPeaks": false,
            "saveQuaternions": false,
            "saveGestureData": false,
            "saveResultFile": true,
            "enableRealtimeData": false,
            "enableVisualFeedback": false,
            "enableHapticFeedback": false,
            "enableVoiceFeedback": false,
            "feedbackType": "gesture"
        ]
        
        UserDefaults.standard.register(defaults: defaults)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
