import SwiftUI

struct CollectionInfo {
    var fields: [String: String]
}

struct GestureStats {
    let name: String
    let count: Int
    let correct: Int
    let accuracy: Double
}

struct StatsSummary {
    let totalSamples: Int
    let totalCorrect: Int
    let overallAccuracy: Double
    let positiveRecall: Double
    let positivePrecision: Double
    let gestureStats: [GestureStats]
}

struct DataDetailView: View {
    let dataFile: DataFile
    @Environment(\.dismiss) private var dismiss
    @State private var statistics: [String: String] = [:]
    @State private var statsSummary: StatsSummary?
    @State private var collectionInfo: CollectionInfo?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 统计信息部分
                        if let stats = statsSummary {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("统计信息")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                // 总体统计
                                VStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        StatCard(
                                            title: "总样本数",
                                            value: "\(stats.totalSamples)",
                                            color: .blue
                                        )
                                        StatCard(
                                            title: "总正确数",
                                            value: "\(stats.totalCorrect)",
                                            color: .green
                                        )
                                    }
                                    
                                    HStack(spacing: 12) {
                                        StatCard(
                                            title: "整体准确率",
                                            value: String(format: "%.1f%%", stats.overallAccuracy * 100),
                                            color: .purple
                                        )
                                        StatCard(
                                            title: "正样本召回率",
                                            value: String(format: "%.1f%%", stats.positiveRecall * 100),
                                            color: .orange
                                        )
                                    }
                                    
                                    StatCard(
                                        title: "正样本精确率",
                                        value: String(format: "%.1f%%", stats.positivePrecision * 100),
                                        color: .pink
                                    )
                                }
                                
                                // 手势详细统计
                                if !stats.gestureStats.isEmpty {
                                    Text("手势统计")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .padding(.top, 8)
                                    
                                    VStack(spacing: 12) {
                                        ForEach(stats.gestureStats, id: \.name) { gesture in
                                            HStack {
                                                Text(gesture.name)
                                                    .font(.headline)
                                                Spacer()
                                                Text("\(gesture.correct)/\(gesture.count)次")
                                                    .foregroundColor(.secondary)
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text(String(format: "%.0f%%", gesture.accuracy * 100))
                                                    .foregroundColor(gesture.accuracy == 1.0 ? .green : .orange)
                                                    .bold()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(10)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // 采集信息部分
                        if let info = collectionInfo {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("采集信息")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                VStack(spacing: 12) {
                                    ForEach(Array(info.fields.keys).sorted(), id: \.self) { key in
                                        InfoRow(
                                            title: key,
                                            value: info.fields[key] ?? ""
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("数据详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        // 读取 statistics.yaml
        let statisticsURL = dataFile.url.appendingPathComponent("statistics.yaml")
        if let content = try? String(contentsOf: statisticsURL, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            var isInStatistics = false
            var isInGestures = false
            var currentGesture: String?
            var totalSamples = 0
            var totalCorrect = 0
            var overallAccuracy: Double = 0
            var positiveRecall: Double = 0
            var positivePrecision: Double = 0
            var gestureStats: [GestureStats] = []
            var currentGestureData: [String: String] = [:]
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let indentLevel = line.prefix(while: { $0 == " " }).count
                
                if trimmedLine == "statistics:" {
                    isInStatistics = true
                    continue
                }
                
                if isInStatistics {
                    if indentLevel == 2 { // statistics 下的直接属性
                        if trimmedLine.hasPrefix("total_samples:") {
                            totalSamples = Int(trimmedLine.replacingOccurrences(of: "total_samples:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if trimmedLine.hasPrefix("total_correct:") {
                            totalCorrect = Int(trimmedLine.replacingOccurrences(of: "total_correct:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if trimmedLine.hasPrefix("overall_accuracy:") {
                            overallAccuracy = Double(trimmedLine.replacingOccurrences(of: "overall_accuracy:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if trimmedLine.hasPrefix("positive_recall:") {
                            positiveRecall = Double(trimmedLine.replacingOccurrences(of: "positive_recall:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if trimmedLine.hasPrefix("positive_precision:") {
                            positivePrecision = Double(trimmedLine.replacingOccurrences(of: "positive_precision:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if trimmedLine == "gestures:" {
                            isInGestures = true
                        }
                    } else if isInGestures {
                        if indentLevel == 4 { // 手势名称层级
                            // 保存前一个手势的数据
                            if let gesture = currentGesture,
                               let count = Int(currentGestureData["count"] ?? "0"),
                               let correct = Int(currentGestureData["correct"] ?? "0"),
                               let accuracy = Double(currentGestureData["accuracy"] ?? "0") {
                                gestureStats.append(GestureStats(
                                    name: gesture,
                                    count: count,
                                    correct: correct,
                                    accuracy: accuracy
                                ))
                            }
                            
                            // 新的手势
                            currentGesture = trimmedLine.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
                            currentGestureData.removeAll()
                        } else if indentLevel == 6 && currentGesture != nil { // 手势属性层级
                            let parts = trimmedLine.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
                            if parts.count == 2 {
                                let key = parts[0].trimmingCharacters(in: .whitespaces)
                                let value = parts[1].trimmingCharacters(in: .whitespaces)
                                currentGestureData[key] = value
                            }
                        }
                    }
                }
            }
            
            // 保存最后一个手势的数据
            if let gesture = currentGesture,
               let count = Int(currentGestureData["count"] ?? "0"),
               let correct = Int(currentGestureData["correct"] ?? "0"),
               let accuracy = Double(currentGestureData["accuracy"] ?? "0") {
                gestureStats.append(GestureStats(
                    name: gesture,
                    count: count,
                    correct: correct,
                    accuracy: accuracy
                ))
            }
            
            statsSummary = StatsSummary(
                totalSamples: totalSamples,
                totalCorrect: totalCorrect,
                overallAccuracy: overallAccuracy,
                positiveRecall: positiveRecall,
                positivePrecision: positivePrecision,
                gestureStats: gestureStats
            )
        }
        
        // 读取 info.yaml 中的 collection 部分
        let infoURL = dataFile.url.appendingPathComponent("info.yaml")
        if let content = try? String(contentsOf: infoURL, encoding: .utf8) {
            // 打印完整的文件内容
            print("info.yaml 完整内容:\n\(content)")
            
            let lines = content.components(separatedBy: .newlines)
            print("文件总行数: \(lines.count)")
            
            var isInCollectionSection = false
            var collectionFields: [String: String] = [:]
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let indentLevel = line.prefix(while: { $0 == " " }).count
                print("处理行: '\(line)', 缩进级别: \(indentLevel)")  // 打印每行的处理信息
                
                if trimmedLine == "collection:" {
                    isInCollectionSection = true
                    print("进入 collection 部分")
                    continue
                }
                
                if isInCollectionSection {
                    if indentLevel == 2 && trimmedLine.contains(":") {  // collection 下的字段有2个空格缩进
                        // 只分割第一个冒号
                        if let colonIndex = trimmedLine.firstIndex(of: ":") {
                            let key = trimmedLine[..<colonIndex].trimmingCharacters(in: .whitespaces)
                            let value = trimmedLine[trimmedLine.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                            collectionFields[key] = value
                            print("添加字段: \(key) = \(value)")
                        }
                    } else if indentLevel == 0 && !trimmedLine.isEmpty {
                        // 遇到无缩进的非空行,说明离开了 collection 部分
                        isInCollectionSection = false
                        print("离开 collection 部分")
                    }
                }
            }
            
            print("读取到的 collection 字段: \(collectionFields)")
            collectionInfo = CollectionInfo(fields: collectionFields)
        } else {
            print("无法读取 info.yaml 文件: \(infoURL.path)")
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct InfoTag: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct StatTag: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
} 

