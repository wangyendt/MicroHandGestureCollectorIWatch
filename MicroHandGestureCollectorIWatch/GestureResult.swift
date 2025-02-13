struct GestureResult: Identifiable {
    let id: String
    let timestamp: Double
    let gesture: String
    let confidence: Double
    let peakValue: Double
    var trueGesture: String
    var bodyGesture: String
    var armGesture: String
    var fingerGesture: String
}

enum GestureNames {
    static let haili = ["单击", "双击", "左摆", "右摆", "握拳", "摊掌", "转腕", "摇手", "其它"]
    static let wayne = ["单击", "双击", "握拳", "左滑", "右滑", "鼓掌", "抖腕", "拍打", "日常"]
}
