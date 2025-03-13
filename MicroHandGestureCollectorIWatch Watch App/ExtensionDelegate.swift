import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidFinishLaunching() {
        // 应用启动时的初始化代码
        print("📱 应用启动完成，准备启动扩展运行时会话")
        ExtendedRuntimeSessionManager.shared.startSession()
        
        // 检查会话状态并打印
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let state = ExtendedRuntimeSessionManager.shared.getSessionState()
            print("📱 扩展运行时会话状态: \(state)")
        }
    }
    
    func applicationDidBecomeActive() {
        // 应用变为活动状态时的代码
        print("📱 应用变为活动状态，确保扩展运行时会话处于活动状态")
        ExtendedRuntimeSessionManager.shared.startSession()
        
        // 检查会话状态并打印
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let state = ExtendedRuntimeSessionManager.shared.getSessionState()
            print("📱 扩展运行时会话状态: \(state)")
        }
    }
    
    func applicationWillResignActive() {
        // 应用即将进入非活动状态时的代码
        print("📱 应用即将进入非活动状态")
        // 注意：我们不在这里停止会话，因为我们希望会话在后台继续运行
    }
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            // 静默完成任务
            print("📱 处理后台任务: \(task)")
            task.setTaskCompletedWithSnapshot(false)
        }
    }
} 