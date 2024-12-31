//
//  ContentView.swift
//  MicroHandGestureCollectorWatchOS Watch App
//
//  Created by wayne on 2024/11/4.
//

import SwiftUI
import WatchConnectivity
import CoreMotion
import WatchKit
import AVFoundation

#if os(watchOS)
import WatchKit
#endif

// 简化反馈管理器结构体
struct FeedbackManager {
    private static let synthesizer = AVSpeechSynthesizer()
    
    // 添加反馈开关
    static var enableVisualFeedback = UserDefaults.standard.bool(forKey: "enableVisualFeedback") || !UserDefaults.standard.contains(forKey: "enableVisualFeedback")
    static var enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback") || !UserDefaults.standard.contains(forKey: "enableHapticFeedback")
    static var enableVoiceFeedback = UserDefaults.standard.bool(forKey: "enableVoiceFeedback") || !UserDefaults.standard.contains(forKey: "enableVoiceFeedback")
    
    static func playFeedback(
        style: WKHapticType? = nil,  // 改为可选类型
        withFlash: Bool? = nil,      // 改为可选类型
        speak text: String? = nil
    ) {
        // 振动反馈
        if let style = style, enableHapticFeedback {
            WKInterfaceDevice.current().play(style)
        }
        
        // 视觉反馈
        if let flash = withFlash, flash && enableVisualFeedback {
            NotificationCenter.default.post(name: .flashScreenBorder, object: nil)
        }
        
        // 语音反馈
        if let text = text, enableVoiceFeedback {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.5
            utterance.volume = 1.0
            synthesizer.speak(utterance)
        }
    }
    
    static func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// 添加通知名称扩展
extension Notification.Name {
    static let flashScreenBorder = Notification.Name("flashScreenBorder")
}

// 修改视觉反馈修饰器
struct FlashBorderModifier: ViewModifier {
    @State private var isFlashing = false
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isFlashing {
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.blue.opacity(0.8), lineWidth: 20)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isFlashing)
            .onReceive(NotificationCenter.default.publisher(for: .flashScreenBorder)) { _ in
                flash()
            }
    }
    
    private func flash() {
        isFlashing = true
        
        // 延迟后重置闪烁状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isFlashing = false
        }
    }
}

// 添加视图扩展
extension View {
    func flashBorder() -> some View {
        modifier(FlashBorderModifier())
    }
}

// 添加 UserDefaults 扩展
extension UserDefaults {
    func contains(forKey key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isCollecting = false
    @State private var selectedHand = "左手"
    @State private var selectedGesture = "单击[正]"
    @State private var selectedForce = "轻"
    
    @State private var showHandPicker = false
    @State private var showGesturePicker = false
    @State private var showForcePicker = false
    
    @State private var showingDataManagement = false
    @State private var showingDeleteAllAlert = false
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    
    @State private var noteText = "静坐"
    
    @AppStorage("userName") private var userName = "王也"
    @State private var showingNameInput = false
    
    // 添加设置相关的状态
    @AppStorage("peakThreshold") private var peakThreshold: Double = 0.3
    @AppStorage("peakWindow") private var peakWindow: Double = 0.6
    @State private var showingSettings = false
    
    let handOptions = ["左手", "右手"]
    let gestureOptions = ["单击[正]", "双击[正]", "握拳[正]", "左滑[正]", "右滑[正]", "左摆[正]", "右摆[正]", "鼓掌[负]", "抖腕[负]", "拍打[负]", "日常[负]"]
    let forceOptions = ["轻", "中", "重"]
    let calculator = CalculatorBridge()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // 手性选择
                Button(action: { showHandPicker = true }) {
                    HStack {
                        Text("手性").font(.headline)
                        Spacer()
                        Text(selectedHand)
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showHandPicker) {
                    List {
                        ForEach(handOptions, id: \.self) { option in
                            Button(action: {
                                selectedHand = option
                                showHandPicker = false
                            }) {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if selectedHand == option {
                                        Text("✓")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 手势选择
                Button(action: { showGesturePicker = true }) {
                    HStack {
                        Text("手势").font(.headline)
                        Spacer()
                        Text(selectedGesture)
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showGesturePicker) {
                    List {
                        ForEach(gestureOptions, id: \.self) { option in
                            Button(action: {
                                selectedGesture = option
                                showGesturePicker = false
                            }) {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if selectedGesture == option {
                                        Text("✓")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 力度选择
                Button(action: { showForcePicker = true }) {
                    HStack {
                        Text("力度").font(.headline)
                        Spacer()
                        Text(selectedForce)
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showForcePicker) {
                    List {
                        ForEach(forceOptions, id: \.self) { option in
                            Button(action: {
                                selectedForce = option
                                showForcePicker = false
                            }) {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if selectedForce == option {
                                        Text("✓")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 姓名输入框
                HStack {
                    Text("姓名").font(.headline)
                    TextField("请输入姓名", text: $userName)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // 新增备注输入框
                HStack {
                    Text("备注").font(.headline)
                    TextField("请输入备注", text: $noteText)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // 添加设置按钮
                Button(action: {
                    showingSettings = true
                }) {
                    HStack {
                        Text("⚙️ 设置")
                            .foregroundColor(.blue)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(
                        peakThreshold: $peakThreshold,
                        peakWindow: $peakWindow,
                        motionManager: motionManager,
                        onSettingsChanged: { threshold, window in
                            motionManager.signalProcessor.updateSettings(
                                peakThreshold: threshold,
                                peakWindow: window
                            )
                        }
                    )
                }
                
                // 添加计数显示
                if isCollecting {
                    Text("已采集: \(motionManager.peakCount) 次")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                // 开始/停止按钮
                Button(action: {
                    guard motionManager.isReady else { return }
                    isCollecting.toggle()
                    
                    if isCollecting {
                        FeedbackManager.playFeedback(
                            style: .success,
                            speak: "开始采集"
                        )
                        motionManager.startDataCollection(
                            name: userName,
                            hand: selectedHand,
                            gesture: selectedGesture,
                            force: selectedForce,
                            note: noteText
                        )
                    } else {
                        FeedbackManager.playFeedback(
                            style: .stop,
                            speak: "停止采集"
                        )
                        WatchConnectivityManager.shared.sendStopSignal()
                        motionManager.stopDataCollection()
                    }
                }) {
                    HStack {
                        if !motionManager.isReady {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isCollecting ? "■ 停止采集" : "● 开始采集")
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isCollecting ? Color.red : Color.blue)
                    .cornerRadius(8)
                }
                .disabled(!motionManager.isReady)
                .padding(.top, 10)
                
                // 导出按钮
                Button(action: {
                    motionManager.exportData()
                }) {
                    HStack {
                        if connectivityManager.isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("⬆️ 导出到iPhone")
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                .disabled(connectivityManager.isSending)
                
                // 状态消息
                if !connectivityManager.lastMessage.isEmpty {
                    Text(connectivityManager.lastMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
                
                // 删除全部数据按钮
                Button(action: {
                    showingDeleteAllAlert = true
                }) {
                    HStack {
                        Text("🗑️ 删除全部数据")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .alert("确认删除", isPresented: $showingDeleteAllAlert) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        deleteAllData()
                    }
                } message: {
                    Text("确定要删除所有数据吗？此操作不可恢复。")
                }
                
                // 数据管理按钮
                Button(action: {
                    showingDataManagement = true
                }) {
                    HStack {
                        Text("📁 数据管理")
                            .foregroundColor(.blue)
                    }
                }
                .sheet(isPresented: $showingDataManagement) {
                    NavigationView {
                        DataManagementView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                
                // 实时数据显示
                if let accData = motionManager.accelerationData {
                    RealTimeDataView(accData: accData, rotationData: motionManager.rotationData)
                }
                
                Text("1024 + 1000 = \(calculator.sum(1000, with: 1024))")
                    .padding()
                
                // 添加时间戳和采样率显示
                VStack(alignment: .leading, spacing: 5) {
                    Text("采样信息").font(.headline)
                    Text(String(format: "时间戳: %llu", connectivityManager.lastTimestamp))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "采样率: %.1f Hz", connectivityManager.samplingRate))
                        .font(.system(.body, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.horizontal, 10)
        }
        .flashBorder()
        .onAppear {
            isCollecting = false
            motionManager.stopDataCollection()
            WatchConnectivityManager.shared.sendStopSignal()
            
            // 添加欢迎语音
            FeedbackManager.playFeedback(speak: " ")
        }
        .onDisappear {
            if isCollecting {
                isCollecting = false
                motionManager.stopDataCollection()
                WatchConnectivityManager.shared.sendStopSignal()
            }
        }
        .sheet(isPresented: $showingNameInput) {
            NavigationView {
                Form {
                    TextField("输入姓名", text: $userName)
                }
                .navigationTitle("设置姓名")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            showingNameInput = false
                        }
                    }
                }
            }
        }
    }
    
    private func deleteAllData() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                if fileURL.lastPathComponent.contains("_右手_") || fileURL.lastPathComponent.contains("_左手_") {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Error deleting all files: \(error)")
        }
    }
}

// 添加实时数据显示组件
struct RealTimeDataView: View {
    let accData: CMAcceleration?
    let rotationData: CMRotationRate?
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let accData = accData {
                Text("加速度计")
                    .font(.headline)
                    .opacity(isLuminanceReduced ? 0.6 : 1.0)
                Text(String(format: "X: %.2f\nY: %.2f\nZ: %.2f",
                          accData.x,
                          accData.y,
                          accData.z))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isLuminanceReduced ? .gray : .green)
            }
            
            if let rotationData = rotationData {
                Text("陀螺仪")
                    .font(.headline)
                    .opacity(isLuminanceReduced ? 0.6 : 1.0)
                Text(String(format: "X: %.2f\nY: %.2f\nZ: %.2f",
                          rotationData.x,
                          rotationData.y,
                          rotationData.z))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isLuminanceReduced ? .gray : .blue)
            }
        }
        .padding()
        .background(Color.black.opacity(isLuminanceReduced ? 0.5 : 0.1))
        .cornerRadius(10)
    }
}

// 添加设置视图
struct SettingsView: View {
    @Binding var peakThreshold: Double
    @Binding var peakWindow: Double
    @AppStorage("savePeaks") private var savePeaks = false
    @AppStorage("saveValleys") private var saveValleys = false
    @AppStorage("saveSelectedPeaks") private var saveSelectedPeaks = false
    @AppStorage("saveQuaternions") private var saveQuaternions = false
    @AppStorage("saveGestureData") private var saveGestureData = false
    
    // 添加反馈设置
    @AppStorage("enableVisualFeedback") private var enableVisualFeedback = true
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback = true
    @AppStorage("enableVoiceFeedback") private var enableVoiceFeedback = true
    
    // 添加反馈类型设置
    @AppStorage("feedbackType") private var feedbackType = "peak" // "peak" 或 "gesture"
    
    @ObservedObject var motionManager: MotionManager
    
    let onSettingsChanged: (Double, Double) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("峰值检测设置")) {
                    HStack {
                        Text("触发阈值")
                        Spacer()
                        Slider(
                            value: $peakThreshold,
                            in: 0.1...1.0,
                            step: 0.1
                        )
                        Text(String(format: "%.1f", peakThreshold))
                            .frame(width: 40)
                    }
                    
                    HStack {
                        Text("窗口大小")
                        Spacer()
                        Slider(
                            value: $peakWindow,
                            in: 0.1...1.0,
                            step: 0.1
                        )
                        Text(String(format: "%.1f", peakWindow))
                            .frame(width: 40)
                    }
                }
                
                Section(header: Text("数据保存设置")) {
                    Toggle("保存所有峰值", isOn: $savePeaks.animation())
                        .onChange(of: savePeaks) { newValue in
                            motionManager.updateSaveSettings(peaks: newValue)
                        }
                    Toggle("保存所有谷值", isOn: $saveValleys.animation())
                        .onChange(of: saveValleys) { newValue in
                            motionManager.updateSaveSettings(valleys: newValue)
                        }
                    Toggle("保存选中峰值", isOn: $saveSelectedPeaks.animation())
                        .onChange(of: saveSelectedPeaks) { newValue in
                            motionManager.updateSaveSettings(selectedPeaks: newValue)
                        }
                    Toggle("保存姿态四元数", isOn: $saveQuaternions.animation())
                        .onChange(of: saveQuaternions) { newValue in
                            motionManager.updateSaveSettings(quaternions: newValue)
                        }
                }
                
                Section(header: Text("手势识别设置")) {
                    Toggle("保存手势数据", isOn: $saveGestureData.animation())
                        .onChange(of: saveGestureData) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "saveGestureData")
                            motionManager.updateSaveSettings(gestureData: newValue)
                        }
                }
                
                Section(header: Text("反馈设置")) {
                    Picker("反馈触发时机", selection: $feedbackType) {
                        Text("峰值检测").tag("peak")
                        Text("手势识别").tag("gesture")
                    }
                    .pickerStyle(.wheel)
                    
                    Toggle("视觉反馈", isOn: $enableVisualFeedback)
                        .onChange(of: enableVisualFeedback) { newValue in
                            FeedbackManager.enableVisualFeedback = newValue
                        }
                    Toggle("振动反馈", isOn: $enableHapticFeedback)
                        .onChange(of: enableHapticFeedback) { newValue in
                            FeedbackManager.enableHapticFeedback = newValue
                        }
                    Toggle("语音反馈", isOn: $enableVoiceFeedback)
                        .onChange(of: enableVoiceFeedback) { newValue in
                            FeedbackManager.enableVoiceFeedback = newValue
                        }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSettingsChanged(peakThreshold, peakWindow)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
