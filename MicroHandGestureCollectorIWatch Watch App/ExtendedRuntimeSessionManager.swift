import WatchKit
import HealthKit

class ExtendedRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = ExtendedRuntimeSessionManager()
    private var session: WKExtendedRuntimeSession?
    private var isSessionActive = false
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()
    
    override init() {
        super.init()
        requestHealthKitPermissions()
    }
    
    private func requestHealthKitPermissions() {
        let typesToShare: Set = [HKObjectType.workoutType()]
        let typesToRead: Set = [HKObjectType.workoutType()]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            if success {
                print("HealthKit authorization granted")
            } else {
                print("HealthKit authorization denied: \(String(describing: error))")
            }
        }
    }
    
    func startSession() {
        guard !isSessionActive else { return }
        
        invalidateSession()
        
        // 创建运动会话以保持高性能模式
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        
        do {
            let session = try HKWorkoutSession(healthStore: HKHealthStore(), configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.workoutSession = session
            self.builder = builder
            
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { (success, error) in
                print("Workout session started: \(success), error: \(String(describing: error))")
            }
        } catch {
            print("Failed to start workout session: \(error)")
        }
        
        // 创建扩展运行时会话
        session = WKExtendedRuntimeSession()
        session?.delegate = self
        session?.start()
    }
    
    func invalidateSession() {
        // 停止运动会话
        workoutSession?.end()
        builder?.endCollection(withEnd: Date()) { (success, error) in
            print("Workout session ended: \(success), error: \(String(describing: error))")
        }
        workoutSession = nil
        builder = nil
        
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