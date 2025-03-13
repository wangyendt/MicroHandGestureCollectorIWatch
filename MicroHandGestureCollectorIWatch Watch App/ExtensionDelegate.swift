import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidFinishLaunching() {
        // 应用启动时的初始化代码
        print("📱 应用启动完成，准备启动扩展运行时会话")
        
        // 确保我们有所有必要的权限
        requestExtendedRuntimeSessionAuthorization()
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
            // 处理后台任务
            print("📱 处理后台任务: \(task)")
            
            if task is WKApplicationRefreshBackgroundTask {
                // 在后台刷新时启动扩展运行时会话
                ExtendedRuntimeSessionManager.shared.startSession()
                print("📱 通过后台刷新任务启动扩展运行时会话")
            }
            
            // 完成任务
            task.setTaskCompletedWithSnapshot(false)
        }
    }
    
    private func requestExtendedRuntimeSessionAuthorization() {
        // 在这里你可以请求必要的授权，例如健康数据访问
        // 这可能是你应用需要的扩展运行时会话所必须的
        
        // 延迟启动会话，确保权限请求有时间完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ExtendedRuntimeSessionManager.shared.startSession()
            
            // 检查会话状态并打印
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let state = ExtendedRuntimeSessionManager.shared.getSessionState()
                print("📱 扩展运行时会话状态: \(state)")
            }
        }
    }
} 