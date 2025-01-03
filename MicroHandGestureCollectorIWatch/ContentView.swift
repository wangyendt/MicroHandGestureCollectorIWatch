//
//  ContentView.swift
//  MicroHandGestureCollectorIWatch
//
//  Created by wayne on 2024/12/6.
//

import SwiftUI
import WatchConnectivity
import Charts

struct ContentView: View {
    @StateObject private var sensorManager = SensorDataManager.shared
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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
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
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    // 连接状态
                    HStack {
                        Image(systemName: sensorManager.isConnected ? "circle.fill" : "circle")
                            .foregroundColor(sensorManager.isConnected ? .green : .red)
                        Text(sensorManager.isConnected ? "已连接到Mac" : "未连接到Mac")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
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
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
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
                    .padding(.horizontal, 8)
                    
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
                    .padding(.horizontal, 8)
                    
                    // 最后更新时间
                    Text("最后更新: \(timeAgoString(from: sensorManager.lastUpdateTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                    
                    Spacer(minLength: 30)
                    
                    // 状态消息
                    if !sensorManager.lastMessage.isEmpty {
                        Text(sensorManager.lastMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical, 20)
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
