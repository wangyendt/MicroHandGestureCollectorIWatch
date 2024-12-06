import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidFinishLaunching() {
        // 应用启动时的初始化代码
    }
    
    func applicationDidBecomeActive() {
        // 应用变为活动状态时的代码
    }
    
    func applicationWillResignActive() {
        // 应用即将进入非活动状态时的代码
    }
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let workoutTask as WKWatchConnectivityRefreshBackgroundTask:
                // 处理后台任务
                workoutTask.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
} 