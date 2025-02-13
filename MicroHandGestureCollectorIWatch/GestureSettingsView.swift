import SwiftUI

struct GestureSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedBodyGestures: Set<String> = []
    @State private var selectedArmGestures: [String: Set<String>] = [:]
    let resourceFiles: [String: [String]]
    let onSave: () -> Void
    
    init(resourceFiles: [String: [String]], onSave: @escaping () -> Void) {
        self.resourceFiles = resourceFiles
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("身体动作选择")) {
                    ForEach(resourceFiles["body_gesture"] ?? [], id: \.self) { gesture in
                        Toggle(isOn: Binding(
                            get: { selectedBodyGestures.contains(gesture) },
                            set: { isSelected in
                                if isSelected {
                                    selectedBodyGestures.insert(gesture)
                                    if selectedArmGestures[gesture] == nil {
                                        selectedArmGestures[gesture] = []
                                    }
                                } else {
                                    selectedBodyGestures.remove(gesture)
                                    selectedArmGestures.removeValue(forKey: gesture)
                                }
                            }
                        )) {
                            Text(gesture)
                        }
                    }
                }
                
                if !selectedBodyGestures.isEmpty {
                    Section(header: Text("手臂动作对应关系")) {
                        ForEach(Array(selectedBodyGestures).sorted(), id: \.self) { bodyGesture in
                            DisclosureGroup(bodyGesture) {
                                ForEach(resourceFiles["arm_gesture"] ?? [], id: \.self) { armGesture in
                                    Toggle(isOn: Binding(
                                        get: { selectedArmGestures[bodyGesture]?.contains(armGesture) ?? false },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedArmGestures[bodyGesture, default: []].insert(armGesture)
                                            } else {
                                                selectedArmGestures[bodyGesture]?.remove(armGesture)
                                            }
                                        }
                                    )) {
                                        Text(armGesture)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("动作组合设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        // 过滤掉没有选择任何手臂动作的身体动作
                        var filteredMapping = selectedArmGestures
                        for (bodyGesture, armGestures) in selectedArmGestures {
                            if armGestures.isEmpty {
                                filteredMapping.removeValue(forKey: bodyGesture)
                            }
                        }
                        settings.gestureMapping = filteredMapping
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 从AppSettings加载现有的映射关系
            selectedArmGestures = settings.gestureMapping
            
            // 如果没有已保存的映射关系，默认选中所有动作
            if selectedArmGestures.isEmpty {
                // 获取所有身体动作
                let bodyGestures = resourceFiles["body_gesture"] ?? []
                let armGestures = Set(resourceFiles["arm_gesture"] ?? [])
                
                // 为每个身体动作设置所有手臂动作
                for bodyGesture in bodyGestures {
                    selectedArmGestures[bodyGesture] = armGestures
                }
            }
            
            // 更新选中的身体动作集合
            selectedBodyGestures = Set(selectedArmGestures.keys)
        }
    }
} 