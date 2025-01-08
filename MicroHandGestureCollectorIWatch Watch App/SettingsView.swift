import SwiftUI
import WatchConnectivity

struct WatchAppSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @Binding var peakThreshold: Double
    @Binding var peakWindow: Double
    @AppStorage("savePeaks") private var savePeaks = false
    @AppStorage("saveValleys") private var saveValleys = false
    @AppStorage("saveSelectedPeaks") private var saveSelectedPeaks = false
    @AppStorage("saveQuaternions") private var saveQuaternions = false
    @AppStorage("saveGestureData") private var saveGestureData = false
    @AppStorage("saveResultFile") private var saveResultFile = true
    @AppStorage("enableRealtimeData") private var enableRealtimeData = false
    
    // 添加反馈设置
    @AppStorage("enableVisualFeedback") private var enableVisualFeedback = true
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback = true
    @AppStorage("enableVoiceFeedback") private var enableVoiceFeedback = true
    
    // 添加反馈类型设置
    @AppStorage("feedbackType") private var feedbackType = "peak" // "peak" 或 "gesture"
    
    @ObservedObject var motionManager: MotionManager
    
    let onSettingsChanged: (Double, Double) -> Void
    
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
                        // 更新本地设置
                        onSettingsChanged(peakThreshold, peakWindow)
                        motionManager.updateSaveSettings(
                            peaks: savePeaks,
                            valleys: saveValleys,
                            selectedPeaks: saveSelectedPeaks,
                            quaternions: saveQuaternions,
                            gestureData: saveGestureData,
                            resultFile: saveResultFile
                        )
                        
                        // 更新反馈设置
                        FeedbackManager.enableVisualFeedback = enableVisualFeedback
                        FeedbackManager.enableHapticFeedback = enableHapticFeedback
                        FeedbackManager.enableVoiceFeedback = enableVoiceFeedback
                        
                        // 保存到 UserDefaults
                        UserDefaults.standard.set(saveGestureData, forKey: "saveGestureData")
                        UserDefaults.standard.set(saveResultFile, forKey: "saveResultFile")
                        
                        // 同步设置到手机
                        if WCSession.default.isReachable {
                            let settings: [String: Any] = [
                                "type": "update_settings",
                                "feedbackType": feedbackType,
                                "peakThreshold": peakThreshold,
                                "peakWindow": peakWindow,
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
                            WCSession.default.sendMessage(settings, replyHandler: nil) { error in
                                print("发送设置更新失败: \(error.localizedDescription)")
                            }
                        }
                        
                        dismiss()
                    }
                }
            }
        }
    }
} 