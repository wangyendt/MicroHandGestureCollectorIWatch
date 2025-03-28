//import WatchKit
//import AVFoundation
//
//class ExtendedRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
//    static let shared = ExtendedRuntimeSessionManager()
//    private var session: WKExtendedRuntimeSession?
//    private var isSessionActive = false
//    private var retryCount = 0
//    private let maxRetries = 5
//    
//    // 添加音频会话，用于保持后台运行
//    private var audioPlayer: AVAudioPlayer?
//    
//    // 添加保活定时器
//    private var keepAliveTimer: Timer?
//    private var keepAliveSoundFrequency: TimeInterval = 30.0 // 30秒播放一次声音
//    private var connectivityRefreshFrequency: TimeInterval = 60.0 // 60秒刷新一次连接
//    
//    override init() {
//        super.init()
//        print("📱 ExtendedRuntimeSessionManager 初始化")
//        setupAudioSession()
//    }
//    
//    private func setupAudioSession() {
//        do {
//            // 创建静音音频文件
//            // 先尝试在主bundle查找
//            var silentSoundUrl = Bundle.main.url(forResource: "silence", withExtension: "mp3")
//            
//            // 如果主bundle中没有，尝试从根bundle查找
//            if silentSoundUrl == nil {
//                silentSoundUrl = Bundle(for: ExtendedRuntimeSessionManager.self).url(forResource: "silence", withExtension: "mp3")
//            }
//            
//            if silentSoundUrl == nil {
//                print("📱 找不到静音音频文件，创建一个1秒钟的静音音频")
//                // 如果没有静音文件，创建一个空的音频缓冲区
//                let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
//                let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: UInt32(44100))!
//                audioBuffer.frameLength = audioBuffer.frameCapacity
//                
//                // 清空缓冲区数据（创建静音）
//                for i in 0..<Int(audioBuffer.frameLength) {
//                    audioBuffer.floatChannelData?.pointee[i] = 0.0
//                }
//                
//                let audioFile = try AVAudioFile(
//                    forWriting: URL(fileURLWithPath: NSTemporaryDirectory() + "silence.caf"),
//                    settings: audioFormat.settings,
//                    commonFormat: .pcmFormatFloat32,
//                    interleaved: false
//                )
//                try audioFile.write(from: audioBuffer)
//                
//                // 使用这个临时文件
//                try self.audioPlayer = AVAudioPlayer(contentsOf: audioFile.url)
//                print("📱 使用动态生成的静音音频")
//            } else {
//                // 使用静音音频文件
//                try self.audioPlayer = AVAudioPlayer(contentsOf: silentSoundUrl!)
//                print("📱 使用资源包中的静音音频: \(silentSoundUrl!.path)")
//            }
//            
//            self.audioPlayer?.numberOfLoops = -1 // 无限循环
//            self.audioPlayer?.volume = 0.01 // 设置为微小的音量而不是0，可能帮助系统识别它为活跃媒体
//            print("📱 音频会话设置完成")
//        } catch {
//            print("📱 设置音频会话失败: \(error.localizedDescription)")
//        }
//    }
//    
//    func startSession() {
//        guard !isSessionActive else { 
//            print("📱 会话已激活，无需重复启动")
//            return 
//        }
//        
//        print("📱 开始启动扩展运行时会话")
//        
//        // 启动音频播放，保持后台运行
//        startBackgroundAudio()
//        
//        // 启动保活定时器
//        startKeepAliveTimer()
//        
//        // 只在需要时创建新会话
//        if session == nil {
//            session = WKExtendedRuntimeSession()
//            session?.delegate = self
//            print("📱 创建新的扩展运行时会话对象")
//        }
//        
//        // 避免重复启动
//        if session?.state != .running {
//            print("📱 调用 session.start() 方法")
//            session?.start()
//        } else {
//            print("📱 会话已处于运行状态: \(String(describing: session?.state.rawValue))")
//        }
//    }
//    
//    private func startKeepAliveTimer() {
//        // 停止可能已存在的定时器
//        keepAliveTimer?.invalidate()
//        
//        // 创建新定时器，每10秒执行一次保活操作
//        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
//            self?.performKeepAliveActions()
//        }
//        
//        // 确保定时器在运行模式下也能触发
//        if let timer = keepAliveTimer {
//            RunLoop.current.add(timer, forMode: .common)
//        }
//        
//        print("📱 启动保活定时器")
//    }
//    
//    private func performKeepAliveActions() {
//        // 获取当前时间，用于周期性执行不同操作
//        let currentTime = Date().timeIntervalSince1970
//        
//        // 检查并确保扩展运行时会话处于活动状态
//        if let session = session, session.state != .running {
//            print("📱 检测到会话非活动状态，尝试重启")
//            self.session = nil
//            startSession()
//        }
//        
//        // 周期性地重新激活音频会话
//        if currentTime.truncatingRemainder(dividingBy: keepAliveSoundFrequency) < 10 {
//            print("📱 执行音频会话保活")
//            stopBackgroundAudio()
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                self.startBackgroundAudio()
//            }
//        }
//        
//        // 周期性地刷新WatchConnectivity连接
//        if currentTime.truncatingRemainder(dividingBy: connectivityRefreshFrequency) < 10 {
//            print("📱 刷新WatchConnectivity连接")
//            WatchConnectivityManager.shared.refreshConnection()
//        }
//        
//        // 模拟用户交互以保持UI响应
//        DispatchQueue.main.async {
//            // 创建并处理一个简单的用户事件来保持UI活跃
//            // 这是一个技巧性操作，需要谨慎使用
//            WKInterfaceDevice.current().play(.click)
//        }
//        
//        print("📱 执行保活操作")
//    }
//    
//    private func startBackgroundAudio() {
//        // 配置音频会话
//        do {
//            let audioSession = AVAudioSession.sharedInstance()
//            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
//            try audioSession.setActive(true)
//            
//            // 确保AudioPlayer有效并开始播放
//            if let player = audioPlayer, !player.isPlaying {
//                player.prepareToPlay()
//                player.play()
//                print("📱 开始播放静音音频以保持后台运行")
//            } else {
//                print("📱 音频播放器未初始化或已在播放")
//            }
//        } catch {
//            print("📱 启动后台音频失败: \(error.localizedDescription)")
//        }
//    }
//    
//    private func stopBackgroundAudio() {
//        audioPlayer?.pause()
//        print("📱 暂停音频播放")
//    }
//    
//    func invalidateSession() {
//        print("📱 准备关闭扩展运行时会话")
//        session?.invalidate()
//        session = nil
//        isSessionActive = false
//        retryCount = 0
//        
//        // 停止音频播放
//        audioPlayer?.stop()
//        
//        // 停止保活定时器
//        keepAliveTimer?.invalidate()
//        keepAliveTimer = nil
//        
//        print("📱 会话已关闭")
//    }
//    
//    // MARK: - WKExtendedRuntimeSessionDelegate
//    
//    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
//        print("📱 扩展运行时会话已成功启动 ✅")
//        isSessionActive = true
//        retryCount = 0
//    }
//    
//    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
//                               didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
//                               error: Error?) {
//        print("📱 扩展运行时会话已失效，原因: \(reason.rawValue), 错误: \(String(describing: error?.localizedDescription))")
//        isSessionActive = false
//        
//        // 记录详细错误信息
//        if let error = error {
//            let nsError = error as NSError
//            print("📱 详细错误: \(nsError.domain), 代码: \(nsError.code)")
//            print("📱 用户信息: \(nsError.userInfo)")
//        }
//        
//        // 确保音频会话仍在运行
//        startBackgroundAudio()
//        
//        // 开始递增重试
//        if retryCount < maxRetries {
//            let delay = Double(retryCount + 1) * 2.0 // 递增延迟
//            retryCount += 1
//            
//            print("📱 尝试第 \(retryCount) 次重新启动会话，延迟 \(delay) 秒")
//            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
//                self?.session = nil // 确保重新创建新的会话
//                self?.startSession()
//            }
//        } else {
//            print("📱 达到最大重试次数 \(maxRetries)，停止尝试启动扩展运行时会话")
//        }
//    }
//    
//    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
//        print("📱 扩展运行时会话即将过期，准备重启")
//        // 静默重启会话
//        startSession()
//    }
//    
//    // 添加获取会话状态的方法
//    func getSessionState() -> String {
//        guard let session = session else {
//            return "会话未创建"
//        }
//        
//        switch session.state {
//        case .running:
//            return "正在运行"
//        case .invalid:
//            return "已失效"
//        default:
//            return "未知状态(\(session.state.rawValue))"
//        }
//    }
//}
