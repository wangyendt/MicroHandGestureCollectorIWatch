//
//  ContentView.swift
//  MicroHandGestureCollectorIWatch
//
//  Created by wayne on 2024/12/6.
//

import SwiftUI
import WatchConnectivity
import Charts

// 添加数组分块扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

struct ContentView: View {
    @StateObject private var sensorManager = SensorDataManager.shared
    @StateObject private var feedbackManager = FeedbackManager.shared
    @StateObject private var bleService = BlePeripheralService.shared  // 添加蓝牙服务状态观察
    @StateObject private var videoRecordingService = VideoRecordingService.shared // 添加视频录制服务
    @State private var accDataX: [(Double, Double)] = [] // (seconds, value)
    @State private var accDataY: [(Double, Double)] = []
    @State private var accDataZ: [(Double, Double)] = []
    @State private var gyroDataX: [(Double, Double)] = []
    @State private var gyroDataY: [(Double, Double)] = []
    @State private var gyroDataZ: [(Double, Double)] = []
    private let maxDataPoints = 100
    @State private var startTime: Date? = nil
    @State private var isEditingIP = false
    @State private var tempIP: String = ""
    
    // 添加防止锁屏的属性
    @State private var idleTimer: Timer?
    @State private var isCollecting = false
    @State private var showingDataManagement = false
    @State private var showingPhoneSettings = false
    @State private var showingWatchSettings = false
    @State private var showingCloudDataManagement = false
    @State private var showingChatView = false
    @State private var showingStopCollectionAlert = false
    
    // 添加视觉反馈状态
    @State private var showingVisualFeedback = false
    @State private var lastGestureResult: (gesture: String, confidence: Double)?
    
    // 添加一个属性来跟踪当前使用的模型
    @AppStorage("whoseModel") private var whoseModel = "haili"
    
    // 添加防抖动属性
    @State private var lastDeleteTime: Date = Date(timeIntervalSince1970: 0)
    private let deleteDebounceInterval: TimeInterval = 0.3  // 1秒内不重复删除
    
    // 添加版本号
    private let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    
    @State private var showingTetrisGame = false
    
    var body: some View {
        NavigationView {
            ZStack {  // 添加ZStack来显示视觉反馈
                ScrollView {
                    VStack(spacing: 30) {
                        // 添加版本号显示
                        HStack {
                            Text("版本: \(version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // 连接设置区域
                        GroupBox(label: Text("连接设置").font(.headline)) {
                            VStack(spacing: 15) {
                                // IP地址设置
                                HStack {
                                    if isEditingIP {
                                        TextField("输入Mac的IP地址", text: $tempIP)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .keyboardType(.numbersAndPunctuation)
                                        Button("保存") {
                                            if isValidIP(tempIP) {
                                                sensorManager.serverHost = tempIP
                                                isEditingIP = false
                                            }
                                        }
                                        .disabled(!isValidIP(tempIP))
                                    } else {
                                        Text("Mac IP: \(sensorManager.serverHost)")
                                        Spacer()
                                        Button("编辑") {
                                            tempIP = sensorManager.serverHost
                                            isEditingIP = true
                                        }
                                    }
                                }
                                
                                // 蓝牙状态
                                HStack {
                                    Image(systemName: bleService.isAdvertising ? "bluetooth" : "bluetooth.slash")
                                        .foregroundColor(bleService.isAdvertising ? .blue : .red)
                                    Text(bleService.isAdvertising ? "蓝牙已启动" : "蓝牙未启动")
                                    Spacer()
                                    if bleService.isConnected {
                                        Text("已连接")
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                // 连接状态
                                HStack {
                                    Image(systemName: sensorManager.isConnected ? "circle.fill" : "circle")
                                        .foregroundColor(sensorManager.isConnected ? .green : .red)
                                    Text(sensorManager.isConnected ? "已连接到Mac" : "未连接到Mac")
                                }
                                
                                // Watch连接状态
                                Group {
                                    if WCSession.default.isReachable {
                                        HStack {
                                            Image(systemName: "applewatch.radiowaves.left.and.right")
                                                .foregroundColor(.green)
                                            Text("Watch已连接")
                                        }
                                    } else {
                                        HStack {
                                            Image(systemName: "applewatch.slash")
                                                .foregroundColor(.red)
                                            Text("Watch未连接")
                                        }
                                    }
                                }
                                
                                // 最后更新时间
                                Text("最后更新: \(timeAgoString(from: sensorManager.lastUpdateTime))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // 状态消息
                                if !sensorManager.lastMessage.isEmpty {
                                    Text(sensorManager.lastMessage)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
//                        // 传感器数据区域
//                        GroupBox(label: Text("传感器数据").font(.headline)) {
//                            VStack(spacing: 20) {
//                                // 加速度计图表
//                                ChartView(
//                                    title: "加速度计 (m/s²)",
//                                    dataX: accDataX,
//                                    dataY: accDataY,
//                                    dataZ: accDataZ,
//                                    xData: sensorManager.lastReceivedData["acc_x"] ?? 0,
//                                    yData: sensorManager.lastReceivedData["acc_y"] ?? 0,
//                                    zData: sensorManager.lastReceivedData["acc_z"] ?? 0
//                                )
//                                .frame(height: 350)
//                                
//                                // 陀螺仪图表
//                                ChartView(
//                                    title: "陀螺仪 (rad/s)",
//                                    dataX: gyroDataX,
//                                    dataY: gyroDataY,
//                                    dataZ: gyroDataZ,
//                                    xData: sensorManager.lastReceivedData["gyro_x"] ?? 0,
//                                    yData: sensorManager.lastReceivedData["gyro_y"] ?? 0,
//                                    zData: sensorManager.lastReceivedData["gyro_z"] ?? 0
//                                )
//                                .frame(height: 350)
//                            }
//                            .padding(.vertical, 8)
//                        }
                        
                        // 控制区域
                        GroupBox(label: Text("数据采集").font(.headline)) {
                            VStack(spacing: 15) {
                                // 本地数据管理按钮
                                Button(action: {
                                    showingDataManagement = true
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.title2)
                                        Text("本地数据")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .sheet(isPresented: $showingDataManagement) {
                                    DataManagementView()
                                }
                                
                                // 云端数据管理按钮
                                Button(action: {
                                    showingCloudDataManagement = true
                                }) {
                                    HStack {
                                        Image(systemName: "cloud.fill")
                                            .font(.title2)
                                        Text("云端数据")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .sheet(isPresented: $showingCloudDataManagement) {
                                    CloudDataManagementView()
                                }
                                
                                // AI助手按钮
                                Button(action: {
                                    showingChatView = true
                                }) {
                                    HStack {
                                        Image(systemName: "message.circle.fill")
                                            .font(.title2)
                                        Text("AI 助手")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .sheet(isPresented: $showingChatView) {
                                    ChatView()
                                }
                                
                                // 导入数据按钮
                                Button(action: {
                                    if WCSession.default.isReachable {
                                        WCSession.default.sendMessage([
                                            "type": "request_export",
                                            "trigger_export": true
                                        ], replyHandler: nil) { error in
                                            print("发送导出请求失败: \(error.localizedDescription)")
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.title2)
                                        Text("从Watch导入数据")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .disabled(!WCSession.default.isReachable)
                                
                                // 设置按钮行
                                HStack(spacing: 10) {
                                    // 手机设置按钮
                                    Button(action: {
                                        showingPhoneSettings = true
                                    }) {
                                        HStack {
                                            Image(systemName: "iphone.gen2")
                                                .font(.title2)
                                            Text("手机设置")
                                                .font(.headline)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.purple)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                    .sheet(isPresented: $showingPhoneSettings) {
                                        PhoneSettingsView()
                                    }
                                    
                                    // 手表设置按钮
                                    Button(action: {
                                        showingWatchSettings = true
                                    }) {
                                        HStack {
                                            Image(systemName: "applewatch")
                                                .font(.title2)
                                            Text("手表设置")
                                                .font(.headline)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.orange)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                    .sheet(isPresented: $showingWatchSettings) {
                                        WatchSettingsView(onComplete: { settings in
                                            // 同步设置到手表
                                            if WCSession.default.isReachable {
                                                var message = settings
                                                message["type"] = "update_settings"
                                                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                                    print("发送设置更新失败: \(error.localizedDescription)")
                                                }
                                            }
                                        })
                                    }
                                }
                                
                                // 开始/停止采集按钮
                                Button(action: {
                                    if isCollecting {
                                        // 显示确认弹窗
                                        showingStopCollectionAlert = true
                                    } else {
                                        startCollection()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isCollecting ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.title2)
                                        Text(isCollecting ? "停止采集" : "开始采集")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isCollecting ? Color.red : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // 添加手势游戏按钮
                        Button(action: {
                            showingTetrisGame = true
                        }) {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.title2)
                                Text("手势游戏")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        // 动作演示模块
                        GroupBox(label: Text("动作演示").font(.headline)) {
                            ActionDemoView()
                        }
                        
                        // 手势识别结果区域
                        GroupBox(label: Text("手势识别结果").font(.headline)) {
                            VStack(spacing: 0) {
                                // 标题栏
                                HStack {
                                    Text("\(sensorManager.gestureResults.count) 个结果")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                
                                // 统计信息
                                VStack(alignment: .leading, spacing: 2) {
                                    let stats = calculateGestureStats(results: sensorManager.gestureResults)
                                    if !stats.gestureCounts.isEmpty {
                                        HStack(spacing: 8) {
                                            Text("整体准确率: \(String(format: "%.1f%%", stats.overallAccuracy * 100))")
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                            Text("召回率: \(String(format: "%.1f%%", stats.positiveRecall * 100))")
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                            Text("精确率: \(String(format: "%.1f%%", stats.positivePrecision * 100))")
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        // 手势统计
                                        HStack(alignment: .top, spacing: 12) {
                                            let sortedGestures = Array(stats.gestureCounts.keys.sorted())
                                            let midIndex = (sortedGestures.count + 1) / 2
                                            
                                            // 左列
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(sortedGestures[..<midIndex], id: \.self) { gesture in
                                                    if let accuracy = stats.gestureAccuracy[gesture] {
                                                        Text("\(gesture): \(stats.gestureCounts[gesture] ?? 0)次 (\(String(format: "%.0f%%", accuracy * 100)))")
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                            
                                            // 右列
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(sortedGestures[midIndex...], id: \.self) { gesture in
                                                    if let accuracy = stats.gestureAccuracy[gesture] {
                                                        Text("\(gesture): \(stats.gestureCounts[gesture] ?? 0)次 (\(String(format: "%.0f%%", accuracy * 100)))")
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                // 表头
                                HStack(spacing: 0) {
                                    // 添加前置空间，使整个内容向右移动
                                    Spacer()
                                        .frame(width: 10)
                                    
                                    Text("时间")
                                        .frame(width: 70, alignment: .center)
                                        .font(.system(size: 15))
                                    Text("手势")
                                        .frame(width: 45, alignment: .center)
                                        .font(.system(size: 15))
                                    Text("置信度")
                                        .frame(width: 55, alignment: .center)
                                        .font(.system(size: 15))
                                    Text("峰值")
                                        .frame(width: 45, alignment: .center)
                                        .font(.system(size: 15))
                                    Text("真实")
                                        .frame(width: 45, alignment: .center)
                                        .font(.system(size: 15))
                                    Spacer(minLength: 0)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 2)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                
                                // 结果列表
                                if sensorManager.gestureResults.isEmpty {
                                    Text("暂无识别结果")
                                        .foregroundColor(.secondary)
                                        .padding()
                                } else {
                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(spacing: 0) {
                                                ForEach(sensorManager.gestureResults.reversed()) { result in
                                                    HStack(spacing: 0) {
                                                        // 添加前置空间，使整个内容向右移动
                                                        Spacer()
                                                            .frame(width: 10)
                                                        
                                                        // 时间列
                                                        Text(String(format: "%.2fs", result.timestamp))
                                                            .frame(width: 70, height: 28, alignment: .center)
                                                            .font(.system(size: 15, design: .monospaced))
                                                        
                                                        // 手势列
                                                        Text(result.gesture)
                                                            .frame(width: 45, height: 28, alignment: .center)
                                                            .font(.system(size: 15))
                                                            .bold()
                                                        
                                                        // 置信度列
                                                        Text(String(format: "%.2f", result.confidence))
                                                            .frame(width: 55, height: 28, alignment: .center)
                                                            .font(.system(size: 15))
                                                            .foregroundColor(result.confidence > 0.8 ? .green : .orange)
                                                        
                                                        // 峰值列
                                                        Text(String(format: "%.2f", result.peakValue))
                                                            .frame(width: 45, height: 28, alignment: .center)
                                                            .font(.system(size: 15))
                                                            .foregroundColor(getPeakValueColor(result.peakValue))
                                                        
                                                        // 真实手势下拉菜单
                                                        Menu {
                                                            // let gestureNames = whoseModel == "haili" ? GestureNames.haili : GestureNames.wayne
                                                            let gestureNames = GestureNames.temp
                                                            ForEach(gestureNames, id: \.self) { gesture in
                                                                Button(action: {
                                                                    if let index = sensorManager.gestureResults.firstIndex(where: { $0.id == result.id }) {
                                                                        sensorManager.gestureResults[index].trueGesture = gesture
                                                                        // 记录真实手势更新
                                                                        sensorManager.updateTrueGesture(id: result.id, gesture: gesture, timestamp: result.timestamp)
                                                                        // 使用消息处理服务发送真实手势更新
                                                                        MessageHandlerService.shared.sendTrueGestureUpdate(id: result.id, trueGesture: gesture)
                                                                    }
                                                                }) {
                                                                    Text(GestureEmoji.getDisplayText(gesture))
                                                                }
                                                            }
                                                        } label: {
                                                            Text(result.trueGesture)
                                                                .frame(width: 45, height: 28, alignment: .center)
                                                                .font(.system(size: 15))
                                                                .foregroundColor(result.trueGesture == result.gesture ? .green : .red)
                                                        }
                                                        .frame(width: 45, height: 28)
                                                        
                                                        Spacer()
                                                            .frame(width: 1)
                                                        
                                                        // 删除按钮
                                                        Button(action: {
                                                            let now = Date()
                                                            // 检查是否在防抖动时间内
                                                            if now.timeIntervalSince(lastDeleteTime) > deleteDebounceInterval {
                                                                withAnimation {
                                                                    sensorManager.deleteResult(result)
                                                                    lastDeleteTime = now
                                                                }
                                                            }
                                                        }) {
                                                            Image(systemName: "trash")
                                                                .foregroundColor(.red)
                                                                .imageScale(.small)
                                                                .font(.system(size: 15))
                                                        }
                                                        .frame(width: 26, height: 28)
                                                    }
                                                    .frame(height: 28)
                                                    .id(result.id)
                                                    .padding(.horizontal, 2)
                                                    .padding(.vertical, 1)
                                                    .background(Color(.systemBackground))
                                                }
                                            }
                                        }
                                        .background(Color(.systemGray6))
                                        .frame(height: 300)
                                        .onChange(of: sensorManager.gestureResults.count) { _ in
                                            // 当有新结果时，自动滚动到最后一个结果
                                            if let lastId = sensorManager.gestureResults.last?.id {
                                                withAnimation {
                                                    proxy.scrollTo(lastId, anchor: .bottom)
                                                }
                                            }
                                        }
                                        // 添加手势优先级设置
                                        .simultaneousGesture(DragGesture().onChanged { _ in })
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .sheet(isPresented: $showingDataManagement) {
                        DataManagementView()
                    }
                }
                
                // 视觉反馈覆盖层
                if showingVisualFeedback {
                    Color.green
                        .opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                }
                
                // 录制状态指示
                if videoRecordingService.isRecording {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text(formatTime(videoRecordingService.recordingTime))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                            .padding(.trailing, 8)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("传感器数据监控")
        }
        .onReceive(sensorManager.$lastReceivedData) { _ in
            updateChartData()
        }
        .onAppear {
            // 禁用空闲计时器（防止锁屏）
            UIApplication.shared.isIdleTimerDisabled = true
            
            // 每30秒触发一次用户活动
            idleTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
                UIDevice.current.isProximityMonitoringEnabled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    UIDevice.current.isProximityMonitoringEnabled = false
                }
            }
        }
        .onDisappear {
            // 恢复空闲计时器
            UIApplication.shared.isIdleTimerDisabled = false
            idleTimer?.invalidate()
            idleTimer = nil
        }
        // 更新：使用新的通知名称监听事件
        .onReceive(NotificationCenter.default.publisher(for: .startCollectionRequested)) { notification in
            if let message = notification.userInfo as? [String: Any],
               message["trigger_collection"] as? Bool == true {
                print("开始采集")
                DispatchQueue.main.async {
                    startCollection()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopCollectionRequested)) { notification in
            if let message = notification.userInfo as? [String: Any],
               message["trigger_collection"] as? Bool == true {
                print("停止采集")
                DispatchQueue.main.async {
                    stopCollection()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gestureResultReceived)) { notification in
            if let message = notification.userInfo as? [String: Any],
               let gesture = message["gesture"] as? String,
               let confidence = message["confidence"] as? Double,
               let timestamp = message["timestamp"] as? Double,
               let peakValue = message["peakValue"] as? Double,
               let id = message["id"] as? String {
                
                print("识别到手势: \(gesture), 置信度: \(confidence)")
                DispatchQueue.main.async {
                    // 播放反馈
                    feedbackManager.playFeedback(gesture: gesture, confidence: confidence)
                    
                    // 显示视觉反馈
                    if feedbackManager.isVisualEnabled {
                        withAnimation {
                            showingVisualFeedback = true
                            // 0.5秒后隐藏视觉反馈
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation {
                                    showingVisualFeedback = false
                                }
                            }
                        }
                    }
                    
                    // 添加到手势识别结果列表
                    let result = GestureResult(
                        id: id,
                        timestamp: timestamp,
                        gesture: gesture,
                        confidence: confidence,
                        peakValue: peakValue,
                        trueGesture: gesture, // 初始时将真实手势设为识别结果
                        bodyGesture: sensorManager.currentBodyGesture != "无" ? sensorManager.currentBodyGesture : "无",
                        armGesture: sensorManager.currentArmGesture != "无" ? sensorManager.currentArmGesture : "无",
                        fingerGesture: sensorManager.currentFingerGesture != "无" ? sensorManager.currentFingerGesture : "无"
                    )
                    sensorManager.gestureResults.append(result)
                    
                    // 使用消息处理服务发送更新
                    let bodyGesture = sensorManager.currentBodyGesture != "无" ? sensorManager.currentBodyGesture : "无"
                    let armGesture = sensorManager.currentArmGesture != "无" ? sensorManager.currentArmGesture : "无"
                    let fingerGesture = sensorManager.currentFingerGesture != "无" ? sensorManager.currentFingerGesture : "无"
                    
                    MessageHandlerService.shared.sendGestureResultUpdate(
                        id: id,
                        bodyGesture: bodyGesture,
                        armGesture: armGesture,
                        fingerGesture: fingerGesture
                    )
                    
                    // 记录手势状态更新
                    sensorManager.actionLogger.logGestureState(
                        id: id, 
                        timestamp: timestamp, 
                        body: bodyGesture, 
                        arm: armGesture, 
                        finger: fingerGesture
                    )
                }
            }
        }
        .alert("确认停止采集", isPresented: $showingStopCollectionAlert) {
            Button("取消", role: .cancel) { }
            Button("停止", role: .destructive) {
                stopCollection()
            }
        } message: {
            Text("确定要停止当前的数据采集吗？")
        }
        .sheet(isPresented: $showingTetrisGame) {
            TetrisGameView()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)秒前"
        }
        return "\(seconds / 60)分\(seconds % 60)秒前"
    }
    
    private func updateChartData() {
        let currentTime = Date()
        if startTime == nil {
            startTime = currentTime
        }
        
        // 计算相对时间（秒）
        let seconds = currentTime.timeIntervalSince(startTime!)
        
        // 更新数据
        accDataX.append((seconds, sensorManager.lastReceivedData["acc_x"] ?? 0))
        accDataY.append((seconds, sensorManager.lastReceivedData["acc_y"] ?? 0))
        accDataZ.append((seconds, sensorManager.lastReceivedData["acc_z"] ?? 0))
        gyroDataX.append((seconds, sensorManager.lastReceivedData["gyro_x"] ?? 0))
        gyroDataY.append((seconds, sensorManager.lastReceivedData["gyro_y"] ?? 0))
        gyroDataZ.append((seconds, sensorManager.lastReceivedData["gyro_z"] ?? 0))
        
        // 移除超出时间窗口的数据点
        let timeWindow = 10.0 // 保持与ChartView中的timeWindow一致
        let cutoffTime = seconds - timeWindow
        
        accDataX.removeAll { $0.0 < cutoffTime }
        accDataY.removeAll { $0.0 < cutoffTime }
        accDataZ.removeAll { $0.0 < cutoffTime }
        gyroDataX.removeAll { $0.0 < cutoffTime }
        gyroDataY.removeAll { $0.0 < cutoffTime }
        gyroDataZ.removeAll { $0.0 < cutoffTime }
    }
    
    // 在停止采集时重置时间
    func resetChartData() {
        startTime = nil
        accDataX.removeAll()
        accDataY.removeAll()
        accDataZ.removeAll()
        gyroDataX.removeAll()
        gyroDataY.removeAll()
        gyroDataZ.removeAll()
    }
    
    // 验证IP地址格式是否正确
    private func isValidIP(_ ip: String) -> Bool {
        let parts = ip.components(separatedBy: ".")
        if parts.count != 4 { return false }
        
        return parts.allSatisfy { part in
            if let num = Int(part) {
                return num >= 0 && num <= 255
            }
            return false
        }
    }
    
    // 添加获取峰值颜色的函数
    private func getPeakValueColor(_ value: Double) -> Color {
        let normalizedValue = min(value, 3.0) / 3.0  // 将值标准化到0~1范围
        
        // 使用从蓝色到红色的渐变
        return Color(
            red: normalizedValue,
            green: 0.3,
            blue: 1.0 - normalizedValue
        )
    }
    
    // 计算手势统计
    private func calculateGestureStats(results: [GestureResult]) -> (
        gestureCounts: [String: Int],
        gestureAccuracy: [String: Double],
        overallAccuracy: Double,
        positiveRecall: Double,
        positivePrecision: Double
    ) {
        var gestureCounts: [String: Int] = [:]
        var correctCounts: [String: Int] = [:]
        let negativeGestures = ["其它", "日常"]  // 定义负样本列表
        
        var totalCount = 0
        var totalCorrect = 0
        var positiveCount = 0  // 正样本总数
        var predictedPositiveCount = 0  // 预测为正样本的总数
        var truePositiveCount = 0  // 预测正确的正样本数
        
        for result in results {
            let trueGesture = result.trueGesture
            let predictedGesture = result.gesture
            
            gestureCounts[trueGesture, default: 0] += 1
            totalCount += 1
            
            // 计算正负样本相关统计
            if !negativeGestures.contains(trueGesture) {
                positiveCount += 1  // 真实标签为正样本
            }
            if !negativeGestures.contains(predictedGesture) {
                predictedPositiveCount += 1  // 预测为正样本
                if predictedGesture == trueGesture {
                    truePositiveCount += 1  // 预测正确的正样本
                }
            }
            
            if predictedGesture == trueGesture {
                correctCounts[trueGesture, default: 0] += 1
                totalCorrect += 1
            }
        }
        
        // 计算每个手势的准确率
        var gestureAccuracy: [String: Double] = [:]
        for (gesture, count) in gestureCounts {
            let correct = correctCounts[gesture] ?? 0
            gestureAccuracy[gesture] = Double(correct) / Double(count)
        }
        
        // 计算整体准确率、召回率和精确率
        let overallAccuracy = totalCount > 0 ? Double(totalCorrect) / Double(totalCount) : 0.0
        let positiveRecall = positiveCount > 0 ? Double(truePositiveCount) / Double(positiveCount) : 0.0
        let positivePrecision = predictedPositiveCount > 0 ? Double(truePositiveCount) / Double(predictedPositiveCount) : 0.0
        
        return (gestureCounts, gestureAccuracy, overallAccuracy, positiveRecall, positivePrecision)
    }
    
    // 开始采集时的处理
    private func startCollection() {
        // 先更新UI状态，确保界面响应
        isCollecting = true
        
        // 发送开始采集消息到 Watch
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([
                "type": "start_collection",
                "trigger_collection": true
            ], replyHandler: nil) { error in
                print("发送开始采集消息失败: \(error.localizedDescription)")
            }
        }
        
        // 如果启用了视频录制，则在后台线程开始录制
        if AppSettings.shared.enableVideoRecording {
            // 直接使用SensorDataManager中的文件夹名
            if let folderName = sensorManager.currentFolderName {
                // 在主线程更新完UI后，异步调用视频录制
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 开始视频录制
                    self.videoRecordingService.startRecording(folderName: folderName)
                }
            }
        }
    }
    
    // 停止采集时的处理
    private func stopCollection() {
        // 先更新UI状态
        isCollecting = false
        
        // 发送停止采集消息到 Watch
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([
                "type": "stop_collection",
                "trigger_collection": true
            ], replyHandler: nil) { error in
                print("发送停止采集消息失败: \(error.localizedDescription)")
            }
        }
        
        // 如果正在录制视频，则停止录制（异步执行）
        if videoRecordingService.isRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.videoRecordingService.stopRecording()
            }
        }
        
        sensorManager.resetState()
        resetChartData()
    }
    
    // 格式化时间为 MM:SS 格式
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 数据显示组件
struct DataView: View {
    let label: String
    let value: Double
    
    var body: some View {
        VStack {
            Text(label)
                .font(.caption)
            Text(String(format: "%.2f", value))
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }
}

struct SensorDataPoint: Identifiable {
    let id = UUID()
    let time: Double
    let value: Double
    let axis: String
}

// 新增一个专门的图表组件
struct SensorChart: View {
    let data: [SensorDataPoint]
    let timeWindow: Double
    
    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value)
            )
            .foregroundStyle(by: .value("Axis", point.axis))
        }
        .chartForegroundStyleScale([
            "X": .red,
            "Y": .green,
            "Z": .blue
        ])
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(String(format: "%.1fs", seconds))
                            .font(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(String(format: "%.1f", value))
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// 修改后的 ChartView
struct ChartView: View {
    let title: String
    let dataX: [(Double, Double)]
    let dataY: [(Double, Double)]
    let dataZ: [(Double, Double)]
    let xData: Double
    let yData: Double
    let zData: Double
    
    private let timeWindow: Double = 10.0
    
    private var chartData: [SensorDataPoint] {
        dataX.map { SensorDataPoint(time: $0.0, value: $0.1, axis: "X") } +
        dataY.map { SensorDataPoint(time: $0.0, value: $0.1, axis: "Y") } +
        dataZ.map { SensorDataPoint(time: $0.0, value: $0.1, axis: "Z") }
    }
    
    private var xRange: ClosedRange<Double> {
        if let maxTime = [dataX.last?.0, dataY.last?.0, dataZ.last?.0].compactMap({ $0 }).max() {
            return (maxTime - timeWindow)...maxTime
        }
        return 0...timeWindow
    }
    
    private var yRange: ClosedRange<Double> {
        let allValues = dataX.map { $0.1 } + dataY.map { $0.1 } + dataZ.map { $0.1 }
        if let minY = allValues.min(), let maxY = allValues.max() {
            let padding = abs(maxY - minY) * 0.1
            return (minY - padding)...(maxY + padding)
        }
        return -10...10
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            SensorChart(data: chartData, timeWindow: timeWindow)
                .chartXScale(domain: xRange)
                .chartYScale(domain: yRange)
                .frame(height: 250)
            
            HStack {
                Text("X: \(String(format: "%.2f", xData))")
                    .foregroundColor(.red)
                    .bold()
                Text("Y: \(String(format: "%.2f", yData))")
                    .foregroundColor(.green)
                    .bold()
                Text("Z: \(String(format: "%.2f", zData))")
                    .foregroundColor(.blue)
                    .bold()
            }
            .font(.system(.body))
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    ContentView()
}
