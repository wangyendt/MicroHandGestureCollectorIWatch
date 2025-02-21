import SwiftUI

struct PhoneSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var feedbackManager = FeedbackManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    // AI API设置
    @AppStorage("aiApiKey") private var aiApiKey = ""
    @AppStorage("aiBaseURL") private var aiBaseURL = "https://api.deepseek.com/v1"
    @AppStorage("aiModel") private var aiModel = "deepseek-chat"
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 8192
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("反馈设置")) {
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
                
                Section(header: Text("阿里云OSS设置")) {
                    TextField("Endpoint", text: Binding(
                        get: { self.settings.ossEndpoint },
                        set: { self.settings.ossEndpoint = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Bucket名称", text: Binding(
                        get: { self.settings.ossBucketName },
                        set: { self.settings.ossBucketName = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API Key", text: Binding(
                        get: { self.settings.ossApiKey },
                        set: { self.settings.ossApiKey = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API Secret", text: Binding(
                        get: { self.settings.ossApiSecret },
                        set: { self.settings.ossApiSecret = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("AI API设置")) {
                    SecureField("API Key", text: $aiApiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Base URL", text: $aiBaseURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("模型名称", text: $aiModel)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Stepper("最大Token数: \(aiMaxTokens)", value: $aiMaxTokens, in: 1024...16384, step: 1024)
                    
                    HStack {
                        Text("温度")
                        Slider(value: Binding(
                            get: { self.settings.aiTemperature },
                            set: { self.settings.aiTemperature = $0 }
                        ), in: 0...1, step: 0.1)
                        Text(String(format: "%.1f", settings.aiTemperature))
                            .frame(width: 40)
                    }
                }
                
                Section(header: Text("飞书机器人设置")) {
                    SecureField("App ID", text: Binding(
                        get: { self.settings.larkAppId },
                        set: { self.settings.larkAppId = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("App Secret", text: Binding(
                        get: { self.settings.larkAppSecret },
                        set: { self.settings.larkAppSecret = $0 }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("群组名称", text: Binding(
                        get: { self.settings.larkGroupName },
                        set: { self.settings.larkGroupName = $0 }
                    ))
                }
            }
            .navigationTitle("手机设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
} 
