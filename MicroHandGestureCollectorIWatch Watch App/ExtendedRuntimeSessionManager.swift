import WatchKit

class ExtendedRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = ExtendedRuntimeSessionManager()
    private var session: WKExtendedRuntimeSession?
    private var isSessionActive = false
    
    override init() {
        super.init()
    }
    
    func startSession() {
        guard !isSessionActive else { return }
        
        // 只在需要时创建新会话
        if session == nil {
            session = WKExtendedRuntimeSession()
            session?.delegate = self
        }
        
        // 避免重复启动
        if session?.state != .running {
            session?.start()
        }
    }
    
    func invalidateSession() {
        session?.invalidate()
        session = nil
        isSessionActive = false
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        isSessionActive = true
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                               didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                               error: Error?) {
        isSessionActive = false
        
        // 静默重启会话
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startSession()
        }
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // 静默重启会话
        startSession()
    }
}