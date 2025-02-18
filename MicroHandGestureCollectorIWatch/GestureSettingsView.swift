import SwiftUI

struct GestureSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedBodyGestures: Set<String> = []
    @State private var selectedArmGestures: [String: Set<String>] = [:]
    @State private var selectedFingerGestures: [String: Set<String>] = [:]
    let resourceFiles: [String: [String]]
    let onSave: () -> Void
    
    init(resourceFiles: [String: [String]], onSave: @escaping () -> Void) {
        self.resourceFiles = resourceFiles
        self.onSave = onSave
        
        // 从 AppSettings 加载已保存的映射关系
        _selectedBodyGestures = State(initialValue: Set(settings.gestureMapping.keys))
        _selectedArmGestures = State(initialValue: settings.gestureMapping)
        
        // 初始化手臂动作和手指动作的映射关系
        var initialFingerGestures = settings.armFingerMapping
        
        // 确保所有手臂动作都有完整的手指动作映射
        if let armGestures = resourceFiles["arm_gesture"],
           let fingerGestures = resourceFiles["finger_gesture"] {
            for armGesture in armGestures {
                if initialFingerGestures[armGesture] == nil {
                    // 如果没有映射关系，设置为全开
                    initialFingerGestures[armGesture] = Set(fingerGestures)
                } else {
                    // 如果有映射关系，确保包含所有手指动作
                    initialFingerGestures[armGesture]?.formUnion(fingerGestures)
                }
            }
        }
        
        _selectedFingerGestures = State(initialValue: initialFingerGestures)
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
                
                Section(header: Text("身体动作和手臂动作关系")) {
                    ForEach(Array(selectedBodyGestures).sorted(), id: \.self) { bodyGesture in
                        NavigationLink(destination: ArmGestureSelectionView(
                            bodyGesture: bodyGesture,
                            selectedArmGestures: $selectedArmGestures,
                            availableArmGestures: resourceFiles["arm_gesture"] ?? []
                        )) {
                            VStack(alignment: .leading) {
                                Text(bodyGesture)
                                Text("已选择 \(selectedArmGestures[bodyGesture]?.count ?? 0) 个手臂动作")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                Section(header: Text("手臂动作和手指动作关系")) {
                    ForEach(resourceFiles["arm_gesture"] ?? [], id: \.self) { armGesture in
                        NavigationLink(destination: FingerGestureSelectionView(
                            armGesture: armGesture,
                            selectedFingerGestures: $selectedFingerGestures,
                            availableFingerGestures: resourceFiles["finger_gesture"] ?? []
                        )) {
                            VStack(alignment: .leading) {
                                Text(armGesture)
                                Text("已选择 \(selectedFingerGestures[armGesture]?.count ?? 0) 个手指动作")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("动作关系设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        // 保存身体动作和手臂动作的映射关系
                        settings.gestureMapping = selectedArmGestures
                        // 保存手臂动作和手指动作的映射关系
                        settings.armFingerMapping = selectedFingerGestures
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

// 手臂动作选择视图
struct ArmGestureSelectionView: View {
    let bodyGesture: String
    @Binding var selectedArmGestures: [String: Set<String>]
    let availableArmGestures: [String]
    
    var body: some View {
        List {
            ForEach(availableArmGestures, id: \.self) { armGesture in
                Toggle(isOn: Binding(
                    get: { selectedArmGestures[bodyGesture]?.contains(armGesture) ?? false },
                    set: { isSelected in
                        if isSelected {
                            if selectedArmGestures[bodyGesture] == nil {
                                selectedArmGestures[bodyGesture] = []
                            }
                            selectedArmGestures[bodyGesture]?.insert(armGesture)
                        } else {
                            selectedArmGestures[bodyGesture]?.remove(armGesture)
                        }
                    }
                )) {
                    Text(armGesture)
                }
            }
        }
        .navigationTitle("\(bodyGesture)的手臂动作")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 手指动作选择视图
struct FingerGestureSelectionView: View {
    let armGesture: String
    @Binding var selectedFingerGestures: [String: Set<String>]
    let availableFingerGestures: [String]
    
    var body: some View {
        List {
            ForEach(availableFingerGestures, id: \.self) { fingerGesture in
                Toggle(isOn: Binding(
                    get: { selectedFingerGestures[armGesture]?.contains(fingerGesture) ?? false },
                    set: { isSelected in
                        if isSelected {
                            if selectedFingerGestures[armGesture] == nil {
                                selectedFingerGestures[armGesture] = []
                            }
                            selectedFingerGestures[armGesture]?.insert(fingerGesture)
                        } else {
                            selectedFingerGestures[armGesture]?.remove(fingerGesture)
                        }
                    }
                )) {
                    Text(fingerGesture)
                }
            }
        }
        .navigationTitle("\(armGesture)的手指动作")
        .navigationBarTitleDisplayMode(.inline)
    }
} 