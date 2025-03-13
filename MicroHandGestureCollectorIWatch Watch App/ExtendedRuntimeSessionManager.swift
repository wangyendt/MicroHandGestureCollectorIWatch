import WatchKit

class ExtendedRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = ExtendedRuntimeSessionManager()
    private var session: WKExtendedRuntimeSession?
    private var isSessionActive = false
    
    override init() {
        super.init()
        print("📱 ExtendedRuntimeSessionManager 初始化")
    }
    
    func startSession() {
        guard !isSessionActive else { 
            print("📱 会话已激活，无需重复启动")
            return 
        }
        
        print("📱 开始启动扩展运行时会话")
        // 只在需要时创建新会话
        if session == nil {
            session = WKExtendedRuntimeSession()
            session?.delegate = self
            print("📱 创建新的扩展运行时会话对象")
        }
        
        // 避免重复启动
        if session?.state != .running {
            print("📱 调用 session.start() 方法")
            session?.start()
        } else {
            print("📱 会话已处于运行状态: \(String(describing: session?.state.rawValue))")
        }
    }
    
    func invalidateSession() {
        print("📱 准备关闭扩展运行时会话")
        session?.invalidate()
        session = nil
        isSessionActive = false
        print("📱 会话已关闭")
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("📱 扩展运行时会话已成功启动 ✅")
        isSessionActive = true
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                               didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                               error: Error?) {
        print("📱 扩展运行时会话已失效，原因: \(reason.rawValue), 错误: \(String(describing: error?.localizedDescription))")
        isSessionActive = false
        
        // 静默重启会话
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            print("📱 尝试重新启动会话")
            self?.startSession()
        }
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("📱 扩展运行时会话即将过期，准备重启")
        // 静默重启会话
        startSession()
    }
    
    // 添加获取会话状态的方法
    func getSessionState() -> String {
        guard let session = session else {
            return "会话未创建"
        }
        
        switch session.state {
        case .running:
            return "正在运行"
        case .invalid:
            return "已失效"
        default:
            return "未知状态(\(session.state.rawValue))"
        }
    }
}