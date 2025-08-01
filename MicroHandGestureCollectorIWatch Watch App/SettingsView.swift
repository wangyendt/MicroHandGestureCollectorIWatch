import SwiftUI
import WatchConnectivity

struct WatchAppSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @Binding var peakThreshold: Double
    @Binding var peakWindow: Double
    @Binding var gestureCooldownWindow: Double
    
    // 数据保存设置，明确指定默认值
    @AppStorage("savePeaks") private var savePeaks: Bool = false
    @AppStorage("saveValleys") private var saveValleys: Bool = false
    @AppStorage("saveSelectedPeaks") private var saveSelectedPeaks: Bool = false
    @AppStorage("saveQuaternions") private var saveQuaternions: Bool = false
    @AppStorage("saveGestureData") private var saveGestureData: Bool = false
    @AppStorage("saveResultFile") private var saveResultFile: Bool = true  // 只有这个默认为 true
    @AppStorage("enableRealtimeData") private var enableRealtimeData: Bool = false
    
    // 反馈设置，明确指定默认值
    @AppStorage("enableVisualFeedback") private var enableVisualFeedback: Bool = false
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback: Bool = false
    @AppStorage("enableVoiceFeedback") private var enableVoiceFeedback: Bool = false
    
    // 反馈类型设置，默认为 "gesture"
    @AppStorage("feedbackType") private var feedbackType: String = "gesture"
    
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
                    
                    HStack {
                        Text("冷却窗长")
                        Spacer()
                        Slider(
                            value: $gestureCooldownWindow,
                            in: 0.1...2.0,
                            step: 0.1
                        )
                        Text(String(format: "%.1f", gestureCooldownWindow))
                            .frame(width: 40)
                    }
                }
                
                Section(header: Text("数据保存设置")) {
                    Toggle("保存所有峰值", isOn: $savePeaks.animation())
                    Toggle("保存所有谷值", isOn: $saveValleys.animation())
                    Toggle("保存选中峰值", isOn: $saveSelectedPeaks.animation())
                    Toggle("保存姿态四元数", isOn: $saveQuaternions.animation())
                }
                
                Section(header: Text("手势识别设置")) {
                    Toggle("保存手势数据", isOn: $saveGestureData.animation())
                    Toggle("保存识别结果", isOn: $saveResultFile.animation())
                    Toggle("发送实时数据", isOn: $enableRealtimeData.animation())
                }
                
                Section(header: Text("反馈设置")) {
                    Picker("反馈触发时机", selection: $feedbackType) {
                        Text("峰值检测").tag("peak")
                        Text("手势识别").tag("gesture")
                    }
                    .pickerStyle(.wheel)
                    
                    Toggle("视觉反馈", isOn: $enableVisualFeedback)
                    Toggle("振动反馈", isOn: $enableHapticFeedback)
                    Toggle("语音反馈", isOn: $enableVoiceFeedback)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // 1. 准备 settings 字典
                        let settings: [String: Any] = [
                            "type": "update_settings", // 保持类型不变，以便BLE和WCS兼容
                            "feedbackType": feedbackType,
                            "peakThreshold": peakThreshold,
                            "peakWindow": peakWindow,
                            "gestureCooldownWindow": gestureCooldownWindow,
                            "saveGestureData": saveGestureData,
                            "savePeaks": savePeaks,
                            "saveValleys": saveValleys,
                            "saveSelectedPeaks": saveSelectedPeaks,
                            "saveQuaternions": saveQuaternions,
                            "saveResultFile": saveResultFile,
                            "enableVisualFeedback": enableVisualFeedback,
                            "enableHapticFeedback": enableHapticFeedback,
                            "enableVoiceFeedback": enableVoiceFeedback,
                            "enableRealtimeData": enableRealtimeData
                        ]
                        
                        // 2. 更新 UserDefaults (虽然@AppStorage会自动做，但显式调用 synchronize 确保立即生效)
                        UserDefaults.standard.set(peakThreshold, forKey: "peakThreshold")
                        UserDefaults.standard.set(peakWindow, forKey: "peakWindow")
                        UserDefaults.standard.set(gestureCooldownWindow, forKey: "gestureCooldownWindow")
                        UserDefaults.standard.set(savePeaks, forKey: "savePeaks")
                        UserDefaults.standard.set(saveValleys, forKey: "saveValleys")
                        UserDefaults.standard.set(saveSelectedPeaks, forKey: "saveSelectedPeaks")
                        UserDefaults.standard.set(saveQuaternions, forKey: "saveQuaternions")
                        UserDefaults.standard.set(saveGestureData, forKey: "saveGestureData")
                        UserDefaults.standard.set(saveResultFile, forKey: "saveResultFile")
                        UserDefaults.standard.set(enableRealtimeData, forKey: "enableRealtimeData")
                        UserDefaults.standard.set(enableVisualFeedback, forKey: "enableVisualFeedback")
                        UserDefaults.standard.set(enableHapticFeedback, forKey: "enableHapticFeedback")
                        UserDefaults.standard.set(enableVoiceFeedback, forKey: "enableVoiceFeedback")
                        UserDefaults.standard.set(feedbackType, forKey: "feedbackType")
                        UserDefaults.standard.synchronize()
                        print("WatchAppSettingsView: Updated UserDefaults.")

                        // 3. 发送通知给 ContentView 应用设置
                        NotificationCenter.default.post(name: .userSettingsUpdatedViaBLE, object: nil, userInfo: settings)
                        print("WatchAppSettingsView: Posted userSettingsUpdatedViaBLE notification.")
                        
                        // 4. 同步设置到手机 (通过 BLE)
                        BleCentralService.shared.sendSettingsUpdate(settings: settings)
                        print("WatchAppSettingsView: Sent settings update via BLE.")
                        
                        // 5. 关闭视图
                        dismiss()
                    }
                }
            }
        }
    }
}

// 定义新的通知名称
extension Notification.Name {
    static let didReceiveSettingsUpdate = Notification.Name("didReceiveSettingsUpdate")
} 
