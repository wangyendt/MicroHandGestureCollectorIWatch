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
    
    // 添加视觉反馈状态
    @State private var showingVisualFeedback = false
    @State private var lastGestureResult: (gesture: String, confidence: Double)?
    
    // 添加一个属性来跟踪当前使用的模型
    @AppStorage("whoseModel") private var whoseModel = "haili"
    
    // 添加防抖动属性
    @State private var lastDeleteTime: Date = Date(timeIntervalSince1970: 0)
    private let deleteDebounceInterval: TimeInterval = 0.3  // 1秒内不重复删除
    
    var body: some View {
        NavigationView {
            ZStack {  // 添加ZStack来显示视觉反馈
                ScrollView {
                    VStack(spacing: 30) {
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
                        
                        // 传感器数据区域
                        GroupBox(label: Text("传感器数据").font(.headline)) {
                            VStack(spacing: 20) {
                                // 加速度计图表
                                ChartView(
                                    title: "加速度计 (m/s²)",
                                    dataX: accDataX,
                                    dataY: accDataY,
                                    dataZ: accDataZ,
                                    xData: sensorManager.lastReceivedData["acc_x"] ?? 0,
                                    yData: sensorManager.lastReceivedData["acc_y"] ?? 0,
                                    zData: sensorManager.lastReceivedData["acc_z"] ?? 0
                                )
                                .frame(height: 350)
                                
                                // 陀螺仪图表
                                ChartView(
                                    title: "陀螺仪 (rad/s)",
                                    dataX: gyroDataX,
                                    dataY: gyroDataY,
                                    dataZ: gyroDataZ,
                                    xData: sensorManager.lastReceivedData["gyro_x"] ?? 0,
                                    yData: sensorManager.lastReceivedData["gyro_y"] ?? 0,
                                    zData: sensorManager.lastReceivedData["gyro_z"] ?? 0
                                )
                                .frame(height: 350)
                            }
                            .padding(.vertical, 8)
                        }
                        
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
                                    isCollecting.toggle()
                                    if isCollecting {
                                        // 发送开始采集消息到 Watch
                                        if WCSession.default.isReachable {
                                            WCSession.default.sendMessage([
                                                "type": "start_collection",
                                                "trigger_collection": true
                                            ], replyHandler: nil) { error in
                                                print("发送开始采集消息失败: \(error.localizedDescription)")
                                            }
                                        }
                                    } else {
                                        // 发送停止采集消息到 Watch
                                        if WCSession.default.isReachable {
                                            WCSession.default.sendMessage([
                                                "type": "stop_collection",
                                                "trigger_collection": true
                                            ], replyHandler: nil) { error in
                                                print("发送停止采集消息失败: \(error.localizedDescription)")
                                            }
                                        }
                                        sensorManager.resetState()
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
                                    Text("时间")
                                        .frame(width: 80, alignment: .leading)
                                        .font(.system(size: 17))
                                    Text("手势")
                                        .frame(width: 50, alignment: .leading)
                                        .font(.system(size: 17))
                                    Text("置信度")
                                        .frame(width: 60, alignment: .leading)
                                        .font(.system(size: 17))
                                    Text("峰值")
                                        .frame(width: 50, alignment: .leading)
                                        .font(.system(size: 17))
                                    Text("真实手势")
                                        .frame(width: 70, alignment: .leading)
                                        .font(.system(size: 17))
                                    Spacer(minLength: 0)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 2)
                                .padding(.vertical, 6)
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
                                                ForEach(sensorManager.gestureResults) { result in
                                                    HStack(spacing: 0) {
                                                        // 时间列
                                                        Text(String(format: "%.2fs", result.timestamp))
                                                            .frame(width: 80, height: 32, alignment: .leading)
                                                            .font(.system(size: 17, design: .monospaced))
                                                        
                                                        // 手势列
                                                        Text(result.gesture)
                                                            .frame(width: 50, height: 32, alignment: .leading)
                                                            .font(.system(size: 17))
                                                            .bold()
                                                        
                                                        // 置信度列
                                                        Text(String(format: "%.2f", result.confidence))
                                                            .frame(width: 60, height: 32, alignment: .leading)
                                                            .font(.system(size: 17))
                                                            .foregroundColor(result.confidence > 0.8 ? .green : .orange)
                                                        
                                                        // 峰值列
                                                        Text(String(format: "%.2f", result.peakValue))
                                                            .frame(width: 50, height: 32, alignment: .leading)
                                                            .font(.system(size: 17))
                                                            .foregroundColor(getPeakValueColor(result.peakValue))
                                                        
                                                        // 真实手势下拉菜单
                                                        Menu {
                                                            let gestureNames = whoseModel == "haili" ? GestureNames.haili : GestureNames.wayne
                                                            ForEach(gestureNames, id: \.self) { gesture in
                                                                Button(action: {
                                                                    if let index = sensorManager.gestureResults.firstIndex(where: { $0.id == result.id }) {
                                                                        sensorManager.gestureResults[index].trueGesture = gesture
                                                                        // 发送更新的真实手势到手表
                                                                        if WCSession.default.isReachable {
                                                                            let message: [String: Any] = [
                                                                                "type": "update_true_gesture",
                                                                                "id": result.id,
                                                                                "true_gesture": gesture
                                                                            ]
                                                                            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                                                                                print("发送真实手势更新失败: \(error.localizedDescription)")
                                                                            }
                                                                        }
                                                                    }
                                                                }) {
                                                                    Text(gesture)
                                                                        .font(.system(size: 17))
                                                                }
                                                            }
                                                        } label: {
                                                            Text(result.trueGesture)
                                                                .font(.system(size: 17))
                                                                .foregroundColor(.blue)
                                                                .frame(width: 50, height: 32, alignment: .leading)
                                                        }
                                                        .frame(width: 50, height: 32)
                                                        
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
                                                                .font(.system(size: 17))
                                                        }
                                                        .frame(width: 30, height: 32)
                                                        .padding(.leading, 8)
                                                    }
                                                    .frame(height: 32)
                                                    .id(result.id)
                                                    .padding(.horizontal, 2)
                                                    .padding(.vertical, 2)
                                                    .background(Color(.systemBackground))
                                                }
                                            }
                                        }
                                        .background(Color(.systemGray6))
                                        .frame(height: 350)
                                        .onChange(of: sensorManager.gestureResults.count) { _ in
                                            // 当有新结果时，自动滚动到最后一个结果
                                            if let lastId = sensorManager.gestureResults.last?.id {
                                                withAnimation {
                                                    proxy.scrollTo(lastId, anchor: .bottom)
                                                }
                                            }
                                        }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReceivedWatchMessage"))) { notification in
            if let message = notification.userInfo as? [String: Any] {
                handleMessage(message)
            }
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
    
    private func handleMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String {
            // 只打印非传感器数据的消息
            if type != "batch_data" && type != "sensor_data" {
                print("iPhone收到消息: \(type)")
            }
            
            switch type {
            case "start_collection":
                print("收到开始采集消息") // 添加调试输出
                if message["trigger_collection"] as? Bool == true {
                    print("准备开始采集") // 添加调试输出
                    DispatchQueue.main.async {
                        isCollecting = true
                    }
                }
            case "stop_collection":
                print("收到停止采集消息") // 添加调试输出
                if message["trigger_collection"] as? Bool == true {
                    print("准备停止采集") // 添加调试输出
                    DispatchQueue.main.async {
                        isCollecting = false
                        sensorManager.resetState()
                        resetChartData() // 重置图表数据
                    }
                }
            case "gesture_result":
                print("收到手势识别结果") // 添加调试输出
                if let gesture = message["gesture"] as? String,
                   let confidence = message["confidence"] as? Double {
                    print("识别到手势: \(gesture), 置信度: \(confidence)") // 添加调试输出
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
                    }
                }
            default:
                break
            }
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
        let negativeGestures = ["其它"]  // 定义负样本列表
        
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
