import WatchKit

class ExtendedRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = ExtendedRuntimeSessionManager()
    private var session: WKExtendedRuntimeSession?
    private var isSessionActive = false
    
    func startSession() {
        guard !isSessionActive else { return }
        
        invalidateSession()
        
        session = WKExtendedRuntimeSession()
        session?.delegate = self
        session?.start()
    }
    
    func invalidateSession() {
        session?.invalidate()
        session = nil
        isSessionActive = false
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session started")
        isSessionActive = true
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                               didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                               error: Error?) {
        print("Session invalidated: \(reason) error: \(String(describing: error))")
        isSessionActive = false
        
        // 尝试重新启动会话
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startSession()
        }
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Session will expire")
        // 在会话即将过期时尝试启动新会话
        startSession()
    }
}