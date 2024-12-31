struct GestureResult: Identifiable {
    let id: String
    let timestamp: Double
    let gesture: String
    let confidence: Double
    let peakValue: Double
}