import SwiftUI

struct PhoneSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var feedbackManager = FeedbackManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    // 清除缓存相关状态
    @State private var showingCleanCacheAlert = false
    @State private var cleanCacheResult = ""
    @State private var showingCleanResultAlert = false
    @State private var selectedResolution: String
    
    // AI API设置
    @AppStorage("aiApiKey") private var aiApiKey = ""
    @AppStorage("aiBaseURL") private var aiBaseURL = "https://api.deepseek.com/v1"
    @AppStorage("aiModel") private var aiModel = "deepseek-chat"
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 8192
    
    init() {
        // 初始化选中的分辨率
        _selectedResolution = State(initialValue: AppSettings.shared.videoResolution)
    }
    
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
                
                Section(header: Text("视频录制")) {
                    Toggle(isOn: Binding(
                        get: { self.settings.enableVideoRecording },
                        set: { self.settings.enableVideoRecording = $0 }
                    )) {
                        Label("录制视频", systemImage: "video")
                    }
                    
                    Picker("视频分辨率", selection: $selectedResolution) {
                        Text("640x480").tag("vga640x480")
                        Text("352x288").tag("cif352x288")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedResolution) { newValue in
                        settings.videoResolution = newValue
                        print("视频分辨率已更改为：\(newValue)")  // 添加调试输出
                    }
                    
                    Text("每次采集时将同步录制视频")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("缓存管理")) {
                    Button(action: {
                        showingCleanCacheAlert = true
                    }) {
                        Label("清除缓存文件", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Text("将删除Videos和Logs目录下的所有文件，但不会影响已同步的数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .alert("清除缓存", isPresented: $showingCleanCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("确认") {
                cleanCache()
            }
        } message: {
            Text("确定要清除缓存吗？")
        }
        .alert("缓存清除结果", isPresented: $showingCleanResultAlert) {
            Button("关闭") { }
        } message: {
            Text(cleanCacheResult)
        }
    }
    
    private func cleanCache() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            cleanCacheResult = "无法获取文档目录"
            showingCleanResultAlert = true
            return
        }
        
        let videosPath = documentsPath.appendingPathComponent("Videos")
        let logsPath = documentsPath.appendingPathComponent("Logs")
        let fileManager = FileManager.default
        var deletedFileCount = 0
        var failedFiles: [String] = []
        
        // 清除视频文件
        if fileManager.fileExists(atPath: videosPath.path) {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: videosPath, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        deletedFileCount += 1
                    } catch {
                        print("删除视频文件失败: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
                        failedFiles.append("视频：\(fileURL.lastPathComponent)")
                    }
                }
            } catch {
                print("读取视频目录失败: \(error.localizedDescription)")
                failedFiles.append("无法读取视频目录")
            }
        }
        
        // 清除日志文件
        if fileManager.fileExists(atPath: logsPath.path) {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: logsPath, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        deletedFileCount += 1
                    } catch {
                        print("删除日志文件失败: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
                        failedFiles.append("日志：\(fileURL.lastPathComponent)")
                    }
                }
            } catch {
                print("读取日志目录失败: \(error.localizedDescription)")
                failedFiles.append("无法读取日志目录")
            }
        }
        
        // 构建结果消息
        if failedFiles.isEmpty {
            cleanCacheResult = "已成功清除\(deletedFileCount)个缓存文件"
        } else {
            cleanCacheResult = "已清除\(deletedFileCount)个文件，但\(failedFiles.count)个文件删除失败"
        }
        
        showingCleanResultAlert = true
    }
} 
