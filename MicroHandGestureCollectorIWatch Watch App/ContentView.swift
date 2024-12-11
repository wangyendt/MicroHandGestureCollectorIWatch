//
//  ContentView.swift
//  MicroHandGestureCollectorWatchOS Watch App
//
//  Created by wayne on 2024/11/4.
//

import SwiftUI
import WatchConnectivity
import CoreMotion

#if os(watchOS)
import WatchKit
#endif

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var isCollecting = false
    @State private var selectedHand = "右手"
    @State private var selectedGesture = "单击[正]"
    @State private var selectedForce = "轻"
    
    @State private var showHandPicker = false
    @State private var showGesturePicker = false
    @State private var showForcePicker = false
    
    @State private var showingDataManagement = false
    @State private var showingDeleteAllAlert = false
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var workoutSession: WKExtendedRuntimeSession?
    
    @State private var noteText = "静坐"
    
    let handOptions = ["左手", "右手"]
    let gestureOptions = ["单击[正]", "双击[正]", "握拳[正]", "左滑[正]", "右滑[正]", "鼓掌[负]", "抖腕[负]", "拍打[负]", "日常[负]"]
    let forceOptions = ["轻", "中", "重"]
    let calculator = CalculatorBridge()
    
    @AppStorage("isCollectingState") private var isCollectingState = false
    
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
                
                // 开始/停止按钮
                Button(action: {
                    guard motionManager.isReady else { return }
                    isCollecting.toggle()
                    if isCollecting {
                        motionManager.startDataCollection(
                            hand: selectedHand,
                            gesture: selectedGesture,
                            force: selectedForce,
                            note: noteText
                        )
                    } else {
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
        .navigationTitle("传感器数据监控")
        .modifier(AlwaysOnModifier(isCollecting: isCollecting))
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                startExtendedSession()
            case .background:
                // 保持后台运行
                if isCollecting {
                    startExtendedSession()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: isCollecting) { oldValue, newValue in
            isCollectingState = newValue
            if newValue {
                startExtendedSession()
            } else {
                ExtendedRuntimeSessionManager.shared.invalidateSession()
            }
        }
        .onAppear {
            if isCollectingState {
                isCollecting = true
                motionManager.startDataCollection(
                    hand: selectedHand,
                    gesture: selectedGesture,
                    force: selectedForce,
                    note: noteText
                )
            }
            startExtendedSession()
        }
        .onDisappear {
            ExtendedRuntimeSessionManager.shared.invalidateSession()
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
    
    private func startExtendedSession() {
        ExtendedRuntimeSessionManager.shared.startSession()
    }
}

// 添加 Always On 显示修饰器
struct AlwaysOnModifier: ViewModifier {
    let isCollecting: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var session: WKExtendedRuntimeSession?
    
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(true)
            .opacity(1.0)
            .brightness(isLuminanceReduced ? 0 : -0.1)
            .onAppear {
                if isCollecting {
                    startSession()
                }
            }
            .onDisappear {
                session?.invalidate()
                session = nil
            }
            .onChange(of: isCollecting) { oldValue, newValue in
                if newValue {
                    startSession()
                } else {
                    session?.invalidate()
                    session = nil
                }
            }
    }
    
    private func startSession() {
        session?.invalidate()
        session = WKExtendedRuntimeSession()
        session?.start()
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

#Preview {
    ContentView()
}
