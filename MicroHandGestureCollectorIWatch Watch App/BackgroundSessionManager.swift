//
//  Back.swift
//  DrStarriseWorld
//
//  Created by daoran on 2025/3/26.
//

import WatchKit

class BackgroundSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    private var runtimeSession: WKExtendedRuntimeSession?

    func startExtendedSession() {
        runtimeSession = WKExtendedRuntimeSession()
        runtimeSession?.delegate = self
        runtimeSession?.start()
    }
    
    // 停止扩展会话
    func stopExtendedSession() {
        runtimeSession?.invalidate()
        runtimeSession = nil
        print("🛑 WKExtendedRuntimeSession 已停止")
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        print("✅ WKExtendedRuntimeSession started")
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        print("⏳ WKExtendedRuntimeSession 即将过期，重新启动")
        startExtendedSession()
    }

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("❌ WKExtendedRuntimeSession 失效: \(reason.rawValue), 错误: \(String(describing: error?.localizedDescription))")
        
        // 重新启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startExtendedSession()
        }
    }
}
