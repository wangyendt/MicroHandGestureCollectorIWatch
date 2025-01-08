import SwiftUI
import WatchConnectivity

struct WatchSettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("peakThreshold") private var peakThreshold: Double = 0.3
    @AppStorage("peakWindow") private var peakWindow: Double = 0.6
    @AppStorage("savePeaks") private var savePeaks = false
    @AppStorage("saveValleys") private var saveValleys = false
    @AppStorage("saveSelectedPeaks") private var saveSelectedPeaks = false
    @AppStorage("saveQuaternions") private var saveQuaternions = false
    @AppStorage("saveGestureData") private var saveGestureData = false
    @AppStorage("saveResultFile") private var saveResultFile = true
    @AppStorage("enableVisualFeedback") private var enableVisualFeedback = true
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback = true
    @AppStorage("enableVoiceFeedback") private var enableVoiceFeedback = true
    @AppStorage("feedbackType") private var feedbackType = "peak"
    @AppStorage("enableRealtimeData") private var enableRealtimeData = false
    
    let onComplete: ([String: Any]) -> Void
    
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
                    Toggle("保存所有峰值", isOn: $savePeaks)
                    Toggle("保存所有谷值", isOn: $saveValleys)
                    Toggle("保存选中峰值", isOn: $saveSelectedPeaks)
                    Toggle("保存姿态四元数", isOn: $saveQuaternions)
                }
                
                Section(header: Text("手势识别设置")) {
                    Toggle("保存手势数据", isOn: $saveGestureData)
                    Toggle("保存识别结果", isOn: $saveResultFile)
                    Toggle("发送实时数据", isOn: $enableRealtimeData)
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
            .navigationTitle("手表设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
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
                        
                        onComplete(settings)
                        dismiss()
                    }
                }
            }
        }
    }
} 