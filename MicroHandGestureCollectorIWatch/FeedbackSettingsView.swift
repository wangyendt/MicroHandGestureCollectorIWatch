import SwiftUI

struct FeedbackSettingsView: View {
    @ObservedObject var feedbackManager = FeedbackManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $feedbackManager.isVibrationEnabled) {
                        Label("振动反馈", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    
                    Toggle(isOn: $feedbackManager.isVisualEnabled) {
                        Label("视觉反馈", systemImage: "eye")
                    }
                    
                    Toggle(isOn: $feedbackManager.isVoiceEnabled) {
                        Label("语音播报", systemImage: "speaker.wave.2")
                    }
                }
            }
            .navigationTitle("反馈设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}