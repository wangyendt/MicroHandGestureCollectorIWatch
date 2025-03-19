//
//  MicroHandGestureCollectorIWatchApp.swift
//  MicroHandGestureCollectorIWatch
//
//  Created by wayne on 2024/12/6.
//

import SwiftUI

@main
struct MicroHandGestureCollectorIWatchApp: App {
    init() {
        // 确保MessageHandlerService在应用启动时初始化
        _ = MessageHandlerService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
