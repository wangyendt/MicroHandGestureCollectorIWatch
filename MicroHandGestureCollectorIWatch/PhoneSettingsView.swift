import SwiftUI

struct PhoneSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var feedbackManager = FeedbackManager.shared
    
    // 阿里云OSS设置
    @AppStorage("ossEndpoint") private var ossEndpoint = "oss-cn-hangzhou.aliyuncs.com"
    @AppStorage("ossBucketName") private var ossBucketName = "wayne-data"
    @AppStorage("ossApiKey") private var ossApiKey = ""
    @AppStorage("ossApiSecret") private var ossApiSecret = ""
    
    // AI API设置
    @AppStorage("aiApiKey") private var aiApiKey = ""
    @AppStorage("aiBaseURL") private var aiBaseURL = "https://api.deepseek.com/v1"
    
    // 飞书机器人设置
    @AppStorage("larkAppId") private var larkAppId = ""
    @AppStorage("larkAppSecret") private var larkAppSecret = ""
    @AppStorage("larkGroupName") private var larkGroupName = "测试群"
    
    // 添加实时数据设置
    @AppStorage("enableRealtimeData") private var enableRealtimeData = false
    
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
                    
                    Toggle(isOn: $enableRealtimeData) {
                        Label("实时数据", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                
                Section(header: Text("阿里云OSS设置")) {
                    TextField("Endpoint", text: $ossEndpoint)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Bucket名称", text: $ossBucketName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API Key", text: $ossApiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API Secret", text: $ossApiSecret)
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
                }
                
                Section(header: Text("飞书机器人设置")) {
                    SecureField("App ID", text: $larkAppId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("App Secret", text: $larkAppSecret)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("群组名称", text: $larkGroupName)
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
