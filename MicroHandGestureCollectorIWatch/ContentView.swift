//
//  ContentView.swift
//  MicroHandGestureCollectorIWatch
//
//  Created by wayne on 2024/12/6.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var sensorManager = SensorDataManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 连接状态
                HStack {
                    Image(systemName: sensorManager.isConnected ? "circle.fill" : "circle")
                        .foregroundColor(sensorManager.isConnected ? .green : .red)
                    Text(sensorManager.isConnected ? "已连接到Mac" : "未连接到Mac")
                }
                .padding()
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
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // 传感器数据显示
                VStack(alignment: .leading, spacing: 15) {
                    Text("实时传感器数据")
                        .font(.headline)
                    
                    // 加速度计数据
                    VStack(alignment: .leading) {
                        Text("加速度计 (m/s²):")
                            .font(.subheadline)
                        HStack {
                            DataView(label: "X", value: sensorManager.lastReceivedData["acc_x"] ?? 0)
                            DataView(label: "Y", value: sensorManager.lastReceivedData["acc_y"] ?? 0)
                            DataView(label: "Z", value: sensorManager.lastReceivedData["acc_z"] ?? 0)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    
                    // 陀螺仪数据
                    VStack(alignment: .leading) {
                        Text("陀螺仪 (rad/s):")
                            .font(.subheadline)
                        HStack {
                            DataView(label: "X", value: sensorManager.lastReceivedData["gyro_x"] ?? 0)
                            DataView(label: "Y", value: sensorManager.lastReceivedData["gyro_y"] ?? 0)
                            DataView(label: "Z", value: sensorManager.lastReceivedData["gyro_z"] ?? 0)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // 最后更新时间
                Text("最后更新: \(timeAgoString(from: sensorManager.lastUpdateTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 状态消息
                if !sensorManager.lastMessage.isEmpty {
                    Text(sensorManager.lastMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
            .navigationTitle("传感器数据监控")
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)秒前"
        }
        return "\(seconds / 60)分\(seconds % 60)秒前"
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

#Preview {
    ContentView()
}
