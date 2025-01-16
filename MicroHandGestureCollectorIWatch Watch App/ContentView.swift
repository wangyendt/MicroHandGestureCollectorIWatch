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
        speak text: String? = nil,
        forceSpeak: Bool = false     // 添加强制播报参数
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
        if let text = text, (enableVoiceFeedback || forceSpeak) {
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
    @AppStorage("selectedHand") private var selectedHand = "左手"
    @AppStorage("selectedGesture") private var selectedGesture = "混合"
    @AppStorage("selectedForce") private var selectedForce = "轻"
    @AppStorage("noteText") private var noteText = "静坐"
    
    @State private var showHandPicker = false
    @State private var showGesturePicker = false
    @State private var showForcePicker = false
    
    @State private var showingDataManagement = false
    @State private var showingDeleteAllAlert = false
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    
    @AppStorage("userName") private var userName = "王也"
    @State private var showingNameInput = false
    
    // 添加设置相关的状态
    @AppStorage("peakThreshold") private var peakThreshold: Double = 0.5
    @AppStorage("peakWindow") private var peakWindow: Double = 0.6
    @State private var showingSettings = false
    
    @AppStorage("selectedGender") private var selectedGender = "男"
    @AppStorage("selectedTightness") private var selectedTightness = "松"
    @State private var showGenderPicker = false
    @State private var showTightnessPicker = false
    
    let handOptions = ["左手", "右手"]
    let gestureOptions = ["混合", "单击[正]", "双击[正]", "握拳[正]",
                          "摊掌[正]", "转腕[正]", "摇手[正]",
                          "左滑[正]", "右滑[正]", "左摆[正]", "右摆[正]",
                          "鼓掌[负]", "抖腕[负]", "拍打[负]", "日常[负]"]
    let forceOptions = ["轻", "中", "重"]
    let calculator = CalculatorBridge()
    let genderOptions = ["男", "女"]
    let tightnessOptions = ["松", "紧"]
    
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
                
                Button(action: { showGenderPicker = true }) {
                    HStack {
                        Text("性别").font(.headline)
                        Spacer()
                        Text(selectedGender)
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showGenderPicker) {
                    List {
                        ForEach(genderOptions, id: \.self) { option in
                            Button(action: {
                                selectedGender = option
                                showGenderPicker = false
                            }) {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if selectedGender == option {
                                        Text("✓")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Button(action: { showTightnessPicker = true }) {
                    HStack {
                        Text("松紧").font(.headline)
                        Spacer()
                        Text(selectedTightness)
                            .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showTightnessPicker) {
                    List {
                        ForEach(tightnessOptions, id: \.self) { option in
                            Button(action: {
                                selectedTightness = option
                                showTightnessPicker = false
                            }) {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if selectedTightness == option {
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
                    WatchAppSettingsView(
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
                            gender: selectedGender,
                            tightness: selectedTightness,
                            note: noteText
                        )
                        // 向iPhone发送开始采集的消息
                        if WCSession.default.isReachable {
                            let message: [String: Any] = [
                                "type": "start_collection" as String,
                                "trigger_collection": true as Bool
                            ]
                            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                print("发送开始采集消息失败: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        FeedbackManager.playFeedback(
                            style: .stop,
                            speak: "停止采集"
                        )
                        // 向iPhone发送停止采集的消息
                        if WCSession.default.isReachable {
                            let message: [String: Any] = [
                                "type": "stop_collection" as String,
                                "trigger_collection": true as Bool
                            ]
                            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                print("发送停止采集消息失败: \(error.localizedDescription)")
                            }
                        }
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
//        .onTapGesture {
//            if isCollecting {
//                motionManager.updateLastTapTime()
//            }
//        }
//        .gesture(
//            DragGesture(minimumDistance: 0)
//                .onChanged { _ in
//                    if isCollecting {
//                        motionManager.updateLastTapTime()
//                    }
//                }
//        )
        .onAppear {
            isCollecting = false
            motionManager.stopDataCollection()
            WatchConnectivityManager.shared.sendStopSignal()
            
            // 设置 MotionManager
            WatchConnectivityManager.shared.setMotionManager(motionManager)
            
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReceivedWatchMessage"))) { notification in
            if let message = notification.userInfo as? [String: Any] {
                handleMessage(message)
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

    private func handleMessage(_ message: [String: Any]) {
        print("处理消息:", message) // 添加调试输出
        if let type = message["type"] as? String {
            switch type {
            case "start_collection":
                print("收到开始采集消息") // 添加调试输出
                if !isCollecting && motionManager.isReady {
                    if message["trigger_collection"] as? Bool == true {
                        print("准备开始采集") // 添加调试输出
                        DispatchQueue.main.async {
                            isCollecting = true
                            FeedbackManager.playFeedback(
                                style: .success,
                                speak: "开始采集"
                            )
                            motionManager.startDataCollection(
                                name: userName,
                                hand: selectedHand,
                                gesture: selectedGesture,
                                force: selectedForce,
                                gender: selectedGender,
                                tightness: selectedTightness,
                                note: noteText
                            )
                        }
                    }
                }
            case "stop_collection":
                print("收到停止采集消息") // 添加调试输出
                if isCollecting {
                    if message["trigger_collection"] as? Bool == true {
                        print("准备停止采集") // 添加调试输出
                        DispatchQueue.main.async {
                            isCollecting = false
                            FeedbackManager.playFeedback(
                                style: .stop,
                                speak: "停止采集"
                            )
                            WatchConnectivityManager.shared.sendStopSignal()
                            motionManager.stopDataCollection()
                        }
                    }
                }
            case "request_export":
                print("收到导出请求") // 添加调试输出
                if message["trigger_export"] as? Bool == true {
                    print("准备导出数据") // 添加调试输出
                    DispatchQueue.main.async {
                        motionManager.exportData()
                    }
                }
            case "update_settings":
                print("收到设置更新") // 添加调试输出
                DispatchQueue.main.async {
                    // 更新本地设置
                    if let feedbackType = message["feedbackType"] as? String {
                        UserDefaults.standard.set(feedbackType, forKey: "feedbackType")
                    }
                    if let peakThreshold = message["peakThreshold"] as? Double {
                        self.peakThreshold = peakThreshold
                        motionManager.signalProcessor.updateSettings(peakThreshold: peakThreshold)
                    }
                    if let peakWindow = message["peakWindow"] as? Double {
                        self.peakWindow = peakWindow
                        motionManager.signalProcessor.updateSettings(peakWindow: peakWindow)
                    }
                    if let saveGestureData = message["saveGestureData"] as? Bool {
                        UserDefaults.standard.set(saveGestureData, forKey: "saveGestureData")
                        motionManager.updateSaveSettings(gestureData: saveGestureData)
                    }
                    if let savePeaks = message["savePeaks"] as? Bool {
                        UserDefaults.standard.set(savePeaks, forKey: "savePeaks")
                        motionManager.updateSaveSettings(peaks: savePeaks)
                    }
                    if let saveValleys = message["saveValleys"] as? Bool {
                        UserDefaults.standard.set(saveValleys, forKey: "saveValleys")
                        motionManager.updateSaveSettings(valleys: saveValleys)
                    }
                    if let saveSelectedPeaks = message["saveSelectedPeaks"] as? Bool {
                        UserDefaults.standard.set(saveSelectedPeaks, forKey: "saveSelectedPeaks")
                        motionManager.updateSaveSettings(selectedPeaks: saveSelectedPeaks)
                    }
                    if let saveQuaternions = message["saveQuaternions"] as? Bool {
                        UserDefaults.standard.set(saveQuaternions, forKey: "saveQuaternions")
                        motionManager.updateSaveSettings(quaternions: saveQuaternions)
                    }
                    if let saveResultFile = message["saveResultFile"] as? Bool {
                        UserDefaults.standard.set(saveResultFile, forKey: "saveResultFile")
                        motionManager.updateSaveSettings(resultFile: saveResultFile)
                    }
                    if let enableVisualFeedback = message["enableVisualFeedback"] as? Bool {
                        UserDefaults.standard.set(enableVisualFeedback, forKey: "enableVisualFeedback")
                        FeedbackManager.enableVisualFeedback = enableVisualFeedback
                    }
                    if let enableHapticFeedback = message["enableHapticFeedback"] as? Bool {
                        UserDefaults.standard.set(enableHapticFeedback, forKey: "enableHapticFeedback")
                        FeedbackManager.enableHapticFeedback = enableHapticFeedback
                    }
                    if let enableVoiceFeedback = message["enableVoiceFeedback"] as? Bool {
                        UserDefaults.standard.set(enableVoiceFeedback, forKey: "enableVoiceFeedback")
                        FeedbackManager.enableVoiceFeedback = enableVoiceFeedback
                    }
                }
            default:
                break
            }
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
    @AppStorage("saveResultFile") private var saveResultFile = true
    
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
                    Toggle("保存识别结果", isOn: $saveResultFile.animation())
                        .onChange(of: saveResultFile) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "saveResultFile")
                            motionManager.updateSaveSettings(resultFile: newValue)
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
