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
    // 添加 ExtensionDelegate 作为委托
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    
    // 添加环境对象来监控应用生命周期
    @Environment(\.scenePhase) private var scenePhase
    
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
            "peakThreshold": 0.5,
            "peakWindow": 0.6,
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
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                print("📱 应用变为活动状态 - 由Scene触发")
                // 应用变为活动状态时，尝试启动ExtendedRuntimeSession
                ExtendedRuntimeSessionManager.shared.startSession()
                
                // 自动开始蓝牙扫描
                bleService.startScanning()
                print("📱 自动启动蓝牙扫描")
                
            case .background:
                print("📱 应用进入后台 - 由Scene触发")
                // 应用进入后台，确保会话继续运行
            case .inactive:
                print("📱 应用变为非活动状态 - 由Scene触发")
            @unknown default:
                print("📱 应用状态未知")
            }
        }
    }
}
