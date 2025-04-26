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
    
    // 添加反馈开关，明确指定默认值
    static var enableVisualFeedback = UserDefaults.standard.bool(forKey: "enableVisualFeedback")
    static var enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback")
    static var enableVoiceFeedback = UserDefaults.standard.bool(forKey: "enableVoiceFeedback")
    
    // 在初始化时设置默认值
    static func initialize() {
        // 如果是首次运行，设置默认值
        if !UserDefaults.standard.contains(forKey: "feedbackType") {
            UserDefaults.standard.set("gesture", forKey: "feedbackType")
        }
        if !UserDefaults.standard.contains(forKey: "enableVisualFeedback") {
            UserDefaults.standard.set(false, forKey: "enableVisualFeedback")
        }
        if !UserDefaults.standard.contains(forKey: "enableHapticFeedback") {
            UserDefaults.standard.set(false, forKey: "enableHapticFeedback")
        }
        if !UserDefaults.standard.contains(forKey: "enableVoiceFeedback") {
            UserDefaults.standard.set(false, forKey: "enableVoiceFeedback")
        }
        UserDefaults.standard.synchronize()
        
        // 更新静态属性
        enableVisualFeedback = UserDefaults.standard.bool(forKey: "enableVisualFeedback")
        enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback")
        enableVoiceFeedback = UserDefaults.standard.bool(forKey: "enableVoiceFeedback")
    }
    
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
    @StateObject private var bleService = BleCentralService.shared  // 添加蓝牙服务
    @StateObject private var motionManager = MotionManager()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isCollecting = false
    @AppStorage("selectedHand") private var selectedHand: String = "左手"
    @AppStorage("selectedGesture") private var selectedGesture: String = "混合"
    @AppStorage("selectedForce") private var selectedForce: String = "轻"
    @AppStorage("noteText") private var noteText: String = "静坐"
    
    @State private var showHandPicker = false
    @State private var showGesturePicker = false
    @State private var showForcePicker = false
    @State private var showGenderPicker = false
    @State private var showTightnessPicker = false
    @State private var showBandTypePicker = false
    @State private var showCrownPicker = false
    
    @State private var showingDataManagement = false
    @State private var showingDeleteAllAlert = false
    @State private var swipeToDeleteOffset: CGFloat = 0
    @State private var swipeToDeleteComplete = false
    private let sliderWidth: CGFloat = 45 // 滑块宽度
    private let swipeThresholdFraction: CGFloat = 0.7 // 滑动完成所需比例
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    
    @AppStorage("userName") private var userName: String = "王也"
    @AppStorage("wristSize") private var wristSize: String = "16"
    @AppStorage("supervisorName") private var supervisorName: String = ""  // 添加监督者姓名
    @State private var showingNameInput = false
    
    // 添加设置相关的状态
    @AppStorage("peakThreshold") private var peakThreshold: Double = 0.5  // peak阈值
    @AppStorage("peakWindow") private var peakWindow: Double = 0.6  // peak窗口
    @State private var showingSettings = false
    
    @AppStorage("selectedGender") private var selectedGender: String = "男"
    @AppStorage("selectedTightness") private var selectedTightness: String = "松"
    
    // 添加表冠位置状态
    @AppStorage("selectedCrownPosition") private var selectedCrownPosition: String = "右"
    
    // 添加表带相关状态
    @AppStorage("selectedBandType") private var selectedBandType: String = "运动"
    
    // 添加版本号
    private let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    
    let handOptions = ["左手", "右手"]
    let gestureOptions = ["混合", "单击[正]", "双击[正]", "握拳[正]",
                          "摊掌[正]", "反掌[正]", "转腕[正]", "旋腕[正]",
                          "左滑[正]", "右滑[正]", "左摆[正]", "右摆[正]",
                          "鼓掌[负]", "抖腕[负]", "拍打[负]", "日常[负]"]
    let forceOptions = ["轻", "中", "重"]
    let calculator = CalculatorBridge()
    let genderOptions = ["男", "女"]
    let tightnessOptions = ["松", "紧"]
    let bandTypeOptions = ["金属", "真皮", "编织", "运动", "橡胶"]
    let crownPositionOptions = ["左", "右"]
    
    // 计算属性，决定是否显示删除按钮
    private var showDeleteButton: Bool {
        return supervisorName != "陈科亦" && supervisorName != "徐森爱"
    }
    
    // Helper view for Hand Picker
    private var handPickerSection: some View {
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
    }
    
    // Helper view for Crown Position Picker
    private var crownPickerSection: some View {
        Button(action: { showCrownPicker = true }) {
            HStack {
                Text("表冠").font(.headline)
                Spacer()
                Text(selectedCrownPosition)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showCrownPicker) {
            List {
                ForEach(crownPositionOptions, id: \.self) { option in
                    Button(action: {
                        selectedCrownPosition = option
                        showCrownPicker = false
                    }) {
                        HStack {
                            Text(option)
                            Spacer()
                            if selectedCrownPosition == option {
                                Text("✓")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper view for Gender Picker
    private var genderPickerSection: some View {
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
    }
    
    // Helper view for Band Type Picker
    private var bandTypePickerSection: some View {
        Button(action: { showBandTypePicker = true }) {
            HStack {
                Text("表带").font(.headline)
                Spacer()
                Text(selectedBandType)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showBandTypePicker) {
            List {
                ForEach(bandTypeOptions, id: \.self) { option in
                    Button(action: {
                        selectedBandType = option
                        showBandTypePicker = false
                    }) {
                        HStack {
                            Text(option)
                            Spacer()
                            if selectedBandType == option {
                                Text("✓")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper view for Tightness Picker
    private var tightnessPickerSection: some View {
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
    }
    
    // Helper view for Gesture Picker
    private var gesturePickerSection: some View {
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
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // 添加版本号显示
                HStack {
                    Text("版本: \(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                
                // Use the helper view
                handPickerSection
                
                // Add Crown Picker Section
                crownPickerSection
                
                // Use the helper view for Gender
                genderPickerSection
                
                // Use the helper view for Band Type
                bandTypePickerSection
                
                // Use the helper view for Tightness
                tightnessPickerSection
                
                // Use the helper view for Gesture
                gesturePickerSection
                
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
                
                // 备注输入框
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
                
                // 新增腕围输入框
                HStack {
                    Text("腕围").font(.headline)
                    TextField("请输入腕围(cm)", text: $wristSize)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // 参与测试者的姓名输入框
                HStack {
                    Text("测试者").font(.headline)
                    TextField("请输入姓名", text: $userName)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                // 添加监督者姓名输入框
                HStack {
                    Text("监督者").font(.headline)
                    TextField("请输入监督者姓名", text: $supervisorName)
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
                        peakWindow: $peakWindow
                    )
                }

                // 添加蓝牙状态显示
                HStack {
                    Image(systemName: bleService.isConnected ? "bolt.circle.fill" : "bolt.circle")
                        .foregroundColor(bleService.isConnected ? .blue : .gray)
                    Text(bleService.isConnected ? "已连接" : (bleService.isScanning ? "扫描中..." : "未连接"))
                        .foregroundColor(bleService.isConnected ? .blue : (bleService.isScanning ? .orange : .gray))
                    Spacer()
                    if bleService.isConnected {
                        Button(action: {
                            bleService.disconnect()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: {
                            if bleService.isScanning {
                                bleService.stopScanning()
                            } else {
                                bleService.startScanning()
                            }
                        }) {
                            Image(systemName: bleService.isScanning ? "stop.circle.fill" : "arrow.clockwise.circle.fill")
                                .foregroundColor(bleService.isScanning ? .red : .blue)
                        }
                    }
                }
                .padding(.horizontal, 8)
                
                // 添加计数器显示
                if bleService.isConnected {
                    Text("计数器: \(bleService.currentValue)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                // 添加计数显示
                if isCollecting {
                    Text("已采集: \(motionManager.peakCount) 次")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                // 开始/停止按钮
                Button(action: {
                    guard motionManager.isReady && !motionManager.isTransitioning else { return }
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
                            note: noteText,
                            wristSize: wristSize,
                            bandType: selectedBandType,
                            supervisorName: supervisorName,  // 添加监督者姓名参数
                            crownPosition: selectedCrownPosition // 添加表冠位置参数
                        )
                        // 向iPhone发送开始采集的消息 (改为BLE)
                        bleService.sendControlMessage(type: "start_collection")
                        /*
                        if WCSession.default.isReachable {
                            let message: [String: Any] = [
                                "type": "start_collection" as String,
                                "trigger_collection": true as Bool
                            ]
                            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                print("发送开始采集消息失败: \\(error.localizedDescription)")
                            }
                        }
                        */
                    } else {
                        FeedbackManager.playFeedback(
                            style: .stop,
                            speak: "停止采集"
                        )
                        // 向iPhone发送停止采集的消息 (改为BLE)
                        bleService.sendControlMessage(type: "stop_collection")
                        /*
                        if WCSession.default.isReachable {
                            let message: [String: Any] = [
                                "type": "stop_collection" as String,
                                "trigger_collection": true as Bool
                            ]
                            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                print("发送停止采集消息失败: \\(error.localizedDescription)")
                            }
                        }
                        */
                        motionManager.stopDataCollection()
                    }
                }) {
                    HStack {
                        if !motionManager.isReady || motionManager.isTransitioning {
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
                    .opacity(motionManager.isTransitioning ? 0.5 : 1.0)  // 添加透明度表示禁用状态
                }
                .disabled(!motionManager.isReady || motionManager.isTransitioning)
                .padding(.top, 10)
                
                // 导出按钮
                Button(action: {
                    guard !motionManager.isTransitioning else { return }
                    motionManager.exportData()
                }) {
                    HStack {
                        if connectivityManager.isSending || motionManager.isTransitioning {
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
                    .opacity((connectivityManager.isSending || motionManager.isTransitioning) ? 0.5 : 1.0)
                }
                .disabled(connectivityManager.isSending || motionManager.isTransitioning)
                
                // 状态消息
                if !connectivityManager.lastMessage.isEmpty {
                    Text(connectivityManager.lastMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }

                // 数据管理按钮
                Button(action: {
                    guard !motionManager.isTransitioning else { return }
                    showingDataManagement = true
                }) {
                    HStack {
                        Text("📁 数据管理")
                            .foregroundColor(.blue)
                    }
                    .opacity(motionManager.isTransitioning ? 0.5 : 1.0)
                }
                .disabled(motionManager.isTransitioning)
                .sheet(isPresented: $showingDataManagement) {
                    NavigationView {
                        DataManagementView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }

                // 滑动删除按钮区域 (移到后面)
                if showDeleteButton {
                    swipeToDeleteButtonArea
                }
                
                // 实时数据显示
                if let accData = motionManager.accelerationData {
                    RealTimeDataView(accData: accData, rotationData: motionManager.rotationData)
                }
                
//                Text("1024 + 1000 = \(calculator.sum(1000, with: 1024))")
//                    .padding()
                
                // 添加时间戳和采样率显示
//                VStack(alignment: .leading, spacing: 5) {
//                    Text("采样信息").font(.headline)
//                    Text(String(format: "时间戳: %llu", connectivityManager.lastTimestamp))
//                        .font(.system(.body, design: .monospaced))
//                    Text(String(format: "采样率: %.1f Hz", connectivityManager.samplingRate))
//                        .font(.system(.body, design: .monospaced))
//                }
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .padding()
//                .background(Color.gray.opacity(0.1))
//                .cornerRadius(10)
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
            
            // 初始化 FeedbackManager
            FeedbackManager.initialize()
            
            // 添加欢迎语音
            FeedbackManager.playFeedback(speak: " ")
            // 重置滑动状态
            swipeToDeleteOffset = 0
            swipeToDeleteComplete = false
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
        // 添加对BLE JSON数据的处理
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveBleJsonData)) { _ in
            // 已由WatchConnectivityManager处理，这里不再需要进行处理
            print("收到BLE JSON数据通知")
        }
        // 添加特定操作的处理
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartCollectionRequested"))) { notification in
            guard !isCollecting && motionManager.isReady else { return }
            if let message = notification.userInfo as? [String: Any], 
               message["trigger_collection"] as? Bool == true {
                print("响应开始采集请求")
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
                        note: noteText,
                        wristSize: wristSize,
                        bandType: selectedBandType,
                        supervisorName: supervisorName,  // 添加监督者姓名参数
                        crownPosition: selectedCrownPosition // 添加表冠位置参数
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopCollectionRequested"))) { notification in
            guard isCollecting else { return }
            if let message = notification.userInfo as? [String: Any], 
               message["trigger_collection"] as? Bool == true {
                print("响应停止采集请求")
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportDataRequested"))) { notification in
            if let message = notification.userInfo as? [String: Any], 
               message["trigger_export"] as? Bool == true {
                print("响应导出数据请求")
                DispatchQueue.main.async {
                    motionManager.exportData()
                }
            }
        }
        // 添加删除结果请求的处理
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteResultRequested"))) { notification in
            if let message = notification.userInfo as? [String: Any],
               let id = message["id"] as? String {
                print("响应删除结果请求，ID: \(id)")
                deleteResultFromFile(id: id)
            }
        }
        // 添加对新BLE设置更新通知的处理
        .onReceive(NotificationCenter.default.publisher(for: .userSettingsUpdatedViaBLE)) { notification in
            print("ContentView: Received userSettingsUpdatedViaBLE notification.")
            if let settings = notification.userInfo as? [String: Any] {
                print("ContentView: Applying settings from BLE: \(settings)")
                applySettings(from: settings)
            }
        }
    }
    
    // 提取出的滑动删除按钮区域
    @ViewBuilder
    private var swipeToDeleteButtonArea: some View {
        VStack {
            if showDeleteButton && !swipeToDeleteComplete {
                GeometryReader { geometry in
                    let trackWidth = geometry.size.width
                    let maxOffset = trackWidth - sliderWidth
                    let currentSwipeThreshold = maxOffset * swipeThresholdFraction

                    ZStack(alignment: .leading) {
                        // 背景
                        Capsule()
                            .fill(Color.red.opacity(0.8))
                            .frame(height: 50)

                        // 使用 HStack 和 Spacer 来居中文本
                        HStack(spacing: 0) { // Use spacing 0 for precise control
                            Spacer()
                                .frame(width: sliderWidth + 5) // 占据滑块宽度 + 5pt 间隙

                            Text("删除全部数据")
                                .font(.footnote)
                                .lineLimit(1)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize() // 防止文本试图填充过多空间

                            Spacer() // 将文本从右侧推开
                        }
                        .frame(height: 50) // 确保 HStack 高度与背景一致

                        // 可拖动滑块 (保持在 ZStack 顶层, 覆盖 HStack 的一部分)
                        Circle()
                            .fill(Color.white)
                            .frame(width: sliderWidth, height: sliderWidth)
                            .overlay(Image(systemName: "trash.fill").foregroundColor(.red))
                            .offset(x: swipeToDeleteOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard !motionManager.isTransitioning else { return }
                                        let newOffset = value.translation.width
                                        swipeToDeleteOffset = max(0, min(newOffset, maxOffset))
                                    }
                                    .onEnded { value in
                                        guard !motionManager.isTransitioning else { return }
                                        if swipeToDeleteOffset >= currentSwipeThreshold {
                                            withAnimation {
                                                swipeToDeleteOffset = maxOffset
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                 swipeToDeleteComplete = true
                                                 showingDeleteAllAlert = true
                                            }
                                        } else {
                                            withAnimation(.spring()) {
                                                swipeToDeleteOffset = 0
                                            }
                                        }
                                    }
                            )
                    }
                    .frame(height: 50)
                }
                .frame(height: 50)
                .opacity(motionManager.isTransitioning ? 0.5 : 1.0)
                .disabled(motionManager.isTransitioning)
                .padding(.vertical, 5)

            } else {
                 // 滑动完成后可以显示不同的视图，或者简单地隐藏
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAllAlert) {
            Button("取消", role: .cancel) {
                withAnimation(.spring()) {
                     swipeToDeleteOffset = 0
                }
                swipeToDeleteComplete = false
            }
            Button("删除", role: .destructive) {
                deleteAllData() // 调用 ContentView 中的方法
                withAnimation(.spring()) {
                     swipeToDeleteOffset = 0
                }
                swipeToDeleteComplete = false
            }
        } message: {
            Text("确定要删除所有数据吗？此操作不可恢复。")
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
    
    private func deleteResultFromFile(id: String) {
        guard let folderURL = motionManager.currentFolderURL else {
            print("❌ 没有设置当前文件夹")
            return
        }

        let resultFileURL = folderURL.appendingPathComponent("result.txt")
        let manualDeletedFileURL = folderURL.appendingPathComponent("manual_deleted.txt")
        
        print("🔍 在文件中查找记录: \(resultFileURL.path)")
        
        guard FileManager.default.fileExists(atPath: resultFileURL.path) else {
            print("❌ 未找到结果文件: \(resultFileURL.path)")
            return
        }
        
        // 首先检查是否已经在manual_deleted.txt中
        if FileManager.default.fileExists(atPath: manualDeletedFileURL.path) {
            do {
                let deletedContent = try String(contentsOf: manualDeletedFileURL, encoding: .utf8)
                let deletedLines = deletedContent.components(separatedBy: .newlines)
                for line in deletedLines {
                    let components = line.components(separatedBy: ",")
                    if components.count > 0 && components[0] == id {
                        print("⚠️ 记录已标记为删除: \(id)")
                        return
                    }
                }
            } catch {
                print("❌ 检查manual_deleted.txt时出错: \(error)")
            }
        }
        
        do {
            print("📝 处理结果文件...")
            print("🗑 查找ID: \(id)")
            
            // 读取文件内容
            let content = try String(contentsOf: resultFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            print("📊 文件总行数: \(lines.count)")
            
            // 查找要删除的记录
            for (index, line) in lines.enumerated() {
                if index == 0 || line.isEmpty { continue }
                
                let components = line.components(separatedBy: ",")
                if components.count >= 6 && components[5] == id {
                    // 找到匹配的记录，保存到manual_deleted.txt
                    if let timestamp = UInt64(components[0]),
                       let relativeTime = Double(components[1]),
                       let confidence = Double(components[3]) {
                        saveManualDeletedRecord(
                            id: id,
                            timestamp: timestamp,
                            relativeTime: relativeTime,
                            gesture: components[2],
                            confidence: confidence
                        )
                        print("✅ 找到并处理要删除的记录")
                        return
                    }
                }
            }
            print("❌ 未找到匹配的记录，ID: \(id)")
        } catch {
            print("❌ 处理结果文件时出错: \(error)")
        }
    }
    
    private func saveManualDeletedRecord(id: String, timestamp: UInt64, relativeTime: Double, gesture: String, confidence: Double) {
        guard let folderURL = motionManager.currentFolderURL else {
            print("❌ 没有设置当前文件夹")
            return
        }
        
        let manualDeletedFileURL = folderURL.appendingPathComponent("manual_deleted.txt")
        print("📝 保存手动删除的记录到: \(manualDeletedFileURL.path)")
        
        // 如果文件不存在，创建文件并写入表头
        if !FileManager.default.fileExists(atPath: manualDeletedFileURL.path) {
            let header = "id,timestamp_ns,relative_timestamp_s,gesture,confidence\n"
            do {
                try header.write(to: manualDeletedFileURL, atomically: true, encoding: .utf8)
                print("创建新的manual_deleted.txt文件")
            } catch {
                print("创建manual_deleted.txt时出错: \(error)")
                return
            }
        }
        
        // 构造记录字符串
        let recordString = String(format: "%@,%llu,%.3f,%@,%.3f\n",
                                id,
                                timestamp,
                                relativeTime,
                                gesture,
                                confidence)
        
        // 追加记录到文件
        if let data = recordString.data(using: .utf8) {
            do {
                let fileHandle = try FileHandle(forWritingTo: manualDeletedFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
                print("✅ 成功保存手动删除的记录")
            } catch {
                print("❌ 保存手动删除的记录时出错: \(error)")
            }
        }
    }

    // 新增：将应用设置的逻辑提取到单独的函数
    private func applySettings(from settings: [String: Any]) {
        // 读取设置值，如果不存在则使用当前的 AppStorage 值或默认值
        let newPeakThreshold = settings["peakThreshold"] as? Double ?? peakThreshold
        let newPeakWindow = settings["peakWindow"] as? Double ?? peakWindow
        let newSavePeaks = settings["savePeaks"] as? Bool ?? UserDefaults.standard.bool(forKey: "savePeaks")
        let newSaveValleys = settings["saveValleys"] as? Bool ?? UserDefaults.standard.bool(forKey: "saveValleys")
        let newSaveSelectedPeaks = settings["saveSelectedPeaks"] as? Bool ?? UserDefaults.standard.bool(forKey: "saveSelectedPeaks")
        let newSaveQuaternions = settings["saveQuaternions"] as? Bool ?? UserDefaults.standard.bool(forKey: "saveQuaternions")
        let newSaveGestureData = settings["saveGestureData"] as? Bool ?? UserDefaults.standard.bool(forKey: "saveGestureData")
        let newSaveResultFile = settings["saveResultFile"] as? Bool ?? UserDefaults.standard.bool(forKey: "saveResultFile")
        let newEnableVisualFeedback = settings["enableVisualFeedback"] as? Bool ?? UserDefaults.standard.bool(forKey: "enableVisualFeedback")
        let newEnableHapticFeedback = settings["enableHapticFeedback"] as? Bool ?? UserDefaults.standard.bool(forKey: "enableHapticFeedback")
        let newEnableVoiceFeedback = settings["enableVoiceFeedback"] as? Bool ?? UserDefaults.standard.bool(forKey: "enableVoiceFeedback")
        let newEnableRealtimeData = settings["enableRealtimeData"] as? Bool ?? UserDefaults.standard.bool(forKey: "enableRealtimeData")
        let newFeedbackType = settings["feedbackType"] as? String ?? UserDefaults.standard.string(forKey: "feedbackType") ?? "gesture"

        // 更新 AppStorage 变量 (确保 UI 反映最新值)
        peakThreshold = newPeakThreshold
        peakWindow = newPeakWindow
        // 更新其他 AppStorage 变量...

        // 更新 MotionManager 的设置
        motionManager.signalProcessor.updateSettings(peakThreshold: newPeakThreshold, peakWindow: newPeakWindow)
        motionManager.updateSaveSettings(
            peaks: newSavePeaks,
            valleys: newSaveValleys,
            selectedPeaks: newSaveSelectedPeaks,
            quaternions: newSaveQuaternions,
            gestureData: newSaveGestureData,
            resultFile: newSaveResultFile
        )
        // 更新 GestureRecognizer 中的保存开关
        motionManager.signalProcessor.gestureRecognizer.updateSettings(saveGestureData: newSaveGestureData)
        // 更新 SignalProcessor 中的结果保存开关
        motionManager.signalProcessor.updateSettings(saveResult: newSaveResultFile)

        // 更新 FeedbackManager 的设置
        FeedbackManager.enableVisualFeedback = newEnableVisualFeedback
        FeedbackManager.enableHapticFeedback = newEnableHapticFeedback
        FeedbackManager.enableVoiceFeedback = newEnableVoiceFeedback

        // 打印日志确认所有设置都被应用
        print("ContentView: Settings applied: threshold=\(newPeakThreshold), window=\(newPeakWindow), savePeaks=\(newSavePeaks), saveValleys=\(newSaveValleys), saveSelected=\(newSaveSelectedPeaks), saveQuat=\(newSaveQuaternions), saveGesture=\(newSaveGestureData), saveResult=\(newSaveResultFile), realTime=\(newEnableRealtimeData), vis=\(newEnableVisualFeedback), haptic=\(newEnableHapticFeedback), voice=\(newEnableVoiceFeedback), feedbackType=\(newFeedbackType)")
    }
}

// 添加实时数据显示组件
struct RealTimeDataView: View {
    let accData: CMAcceleration?
    let rotationData: CMRotationRate?
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
//            if let accData = accData {
//                Text("加速度计")
//                    .font(.headline)
//                    .opacity(isLuminanceReduced ? 0.6 : 1.0)
//                Text(String(format: "X: %.2f\nY: %.2f\nZ: %.2f",
//                          accData.x,
//                          accData.y,
//                          accData.z))
//                    .font(.system(.body, design: .monospaced))
//                    .foregroundColor(isLuminanceReduced ? .gray : .green)
//            }
//            
//            if let rotationData = rotationData {
//                Text("陀螺仪")
//                    .font(.headline)
//                    .opacity(isLuminanceReduced ? 0.6 : 1.0)
//                Text(String(format: "X: %.2f\nY: %.2f\nZ: %.2f",
//                          rotationData.x,
//                          rotationData.y,
//                          rotationData.z))
//                    .font(.system(.body, design: .monospaced))
//                    .foregroundColor(isLuminanceReduced ? .gray : .blue)
//            }
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
