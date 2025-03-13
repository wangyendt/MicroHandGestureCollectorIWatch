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
    
    init() {
        print("📱 应用初始化")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
