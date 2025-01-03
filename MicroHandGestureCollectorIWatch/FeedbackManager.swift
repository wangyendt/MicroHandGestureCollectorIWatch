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
    
    private let synthesizer = AVSpeechSynthesizer()
    private let generator = UINotificationFeedbackGenerator()
    
    private init() {
        // 从UserDefaults读取设置，默认都开启
        self.isVibrationEnabled = UserDefaults.standard.bool(forKey: "isVibrationEnabled", defaultValue: true)
        self.isVisualEnabled = UserDefaults.standard.bool(forKey: "isVisualEnabled", defaultValue: true)
        self.isVoiceEnabled = UserDefaults.standard.bool(forKey: "isVoiceEnabled", defaultValue: true)
        
        // 预热触觉反馈生成器
        generator.prepare()
    }
    
    func playFeedback(gesture: String, confidence: Double) {
        print("播放反馈 - 振动: \(isVibrationEnabled), 视觉: \(isVisualEnabled), 语音: \(isVoiceEnabled)")
        
        if isVibrationEnabled {
            // 触觉反馈
            generator.notificationOccurred(.success)
            generator.prepare() // 为下一次反馈做准备
        }
        
        if isVoiceEnabled {
            // 语音播报
            let utterance = AVSpeechUtterance(string: "\(gesture)")
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.5
            synthesizer.speak(utterance)
        }
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
