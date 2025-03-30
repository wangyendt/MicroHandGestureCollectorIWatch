import Foundation
import AVFoundation
import UIKit

class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()
    
    @Published var isVibrationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVibrationEnabled, forKey: "isVibrationEnabled")
        }
    }
    
    @Published var isVisualEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVisualEnabled, forKey: "isVisualEnabled")
        }
    }
    
    @Published var isVoiceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceEnabled, forKey: "isVoiceEnabled")
        }
    }
    
    // 使用两个独立的语音合成器，以支持同时播报
    private let gestureSynthesizer = AVSpeechSynthesizer() // 用于手势播报
    private let promptSynthesizer = AVSpeechSynthesizer()  // 用于提示播报
    private let generator = UINotificationFeedbackGenerator()
    private var reminderTimer: Timer?
    
    private init() {
        // 从UserDefaults读取设置，默认只开启语音播报
        self.isVibrationEnabled = UserDefaults.standard.bool(forKey: "isVibrationEnabled", defaultValue: false)
        self.isVisualEnabled = UserDefaults.standard.bool(forKey: "isVisualEnabled", defaultValue: false)
        self.isVoiceEnabled = UserDefaults.standard.bool(forKey: "isVoiceEnabled", defaultValue: true)
        
        // 预热触觉反馈生成器
        generator.prepare()
        
        // 监听采集开始和停止的通知
        NotificationCenter.default.addObserver(self, selector: #selector(handleStartCollection), name: .startCollectionRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStopCollection), name: .stopCollectionRequested, object: nil)
    }
    
    @objc private func handleStartCollection(_ notification: Notification) {
        // 确保定时器只被创建一次
        if reminderTimer == nil {
            startReminderTimer()
        }
    }
    
    @objc private func handleStopCollection(_ notification: Notification) {
        stopReminderTimer()
    }
    
    private func startReminderTimer() {
        // 创建定时器，每隔60秒播报一次提示
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.playPromptMessage("滑动手表屏幕")
        }
        // 不在开始时立即播放提示
    }
    
    private func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }
    
    func playFeedback(gesture: String, confidence: Double) {
        print("播放反馈 - 振动: \(isVibrationEnabled), 视觉: \(isVisualEnabled), 语音: \(isVoiceEnabled)")
        
        if isVibrationEnabled {
            // 触觉反馈
            generator.notificationOccurred(.success)
            generator.prepare() // 为下一次反馈做准备
        }
        
        if isVoiceEnabled {
            // 使用手势语音合成器播报手势
            playGestureMessage("\(gesture)")
        }
    }
    
    // 播放手势消息（使用gestureSynthesizer）
    func playGestureMessage(_ text: String) {
        guard isVoiceEnabled else { return }
        
        // 使用后台线程执行语音合成，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.5
            
            // 回到主线程播放语音
            DispatchQueue.main.async {
                self.gestureSynthesizer.speak(utterance)
            }
        }
    }
    
    // 播放提示消息（使用promptSynthesizer）
    func playPromptMessage(_ text: String) {
        guard isVoiceEnabled else { return }
        
        // 使用后台线程执行语音合成，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.5
            
            // 回到主线程播放语音
            DispatchQueue.main.async {
                self.promptSynthesizer.speak(utterance)
            }
        }
    }
    
    // 保留原方法以兼容现有代码调用
    func playTextMessage(_ text: String) {
        playGestureMessage(text)
    }
}

// 扩展UserDefaults以添加默认值支持
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if self.object(forKey: key) == nil {
            return defaultValue
        }
        return self.bool(forKey: key)
    }
}
