import SwiftUI
import AVKit
import ios_tools_lib

struct DemoGroup: Identifiable {
    let id = UUID()
    let armGesture: String
    let bodyGesture: String
    let fingerGesture: String
}

struct ActionDemoView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var infoMessage = "正在检查资源文件..."
    @State private var isLoading = false
    @State private var resourceStats: [String: Int] = [:]
    @State private var currentGifURL: URL?
    @State private var currentVideoURL: URL?
    @State private var currentImageURL: URL?
    
    // 添加组合管理相关的状态
    @State private var allGroups: [DemoGroup] = []
    @State private var currentGroupIndex = 0
    @State private var resourceFiles: [String: [String]] = [:]
    @State private var shuffleSeed: UInt16
    
    private let cloudPrefix = "micro_hand_gesture/demo_videos/"
    private let categories = ["arm_gesture", "body_gesture", "finger_gesture"]
    
    init() {
        // 初始化时生成随机种子
        let seed = UInt16.random(in: 0...UInt16.max)
        _shuffleSeed = State(initialValue: seed)
    }
    
    private var oss: AliyunOSS {
        AliyunOSS(
            endpoint: settings.ossEndpoint,
            bucketName: settings.ossBucketName,
            apiKey: settings.ossApiKey,
            apiSecret: settings.ossApiSecret,
            verbose: true
        )
    }
    
    private var currentGroup: DemoGroup? {
        guard !allGroups.isEmpty else { return nil }
        return allGroups[currentGroupIndex]
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // 动作演示标题和刷新按钮
            HStack {
                Text("当前组合")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task {
                        await checkAndDownloadResources()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(isLoading)
            }
            .padding(.horizontal)
            
            // 信息提示控件
            VStack(spacing: 8) {
                if let group = currentGroup {
                    Text("第 \(currentGroupIndex + 1)/\(allGroups.count) 组")
                        .font(.system(size: 15))
                        .foregroundColor(.blue)
                    
                    Text("随机种子：\(shuffleSeed)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("手臂动作：\(group.armGesture) (共\(resourceStats["arm_gesture"] ?? 0)个)")
                        Text("身体动作：\(group.bodyGesture) (共\(resourceStats["body_gesture"] ?? 0)个)")
                        Text("手指动作：\(group.fingerGesture) (共\(resourceStats["finger_gesture"] ?? 0)个)")
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                } else {
                    Text(infoMessage)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // 导航按钮
            HStack(spacing: 20) {
                // 上一组按钮
                Button(action: {
                    showPreviousGroup()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("上一组")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isLoading || allGroups.isEmpty)
                
                // 下一组按钮
                Button(action: {
                    showNextGroup()
                }) {
                    HStack {
                        Text("下一组")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isLoading || allGroups.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .task {
            await checkAndDownloadResources()
        }
    }
    
    private func showNextGroup() {
        guard !allGroups.isEmpty else { return }
        currentGroupIndex = (currentGroupIndex + 1) % allGroups.count
    }
    
    private func showPreviousGroup() {
        guard !allGroups.isEmpty else { return }
        currentGroupIndex = (currentGroupIndex - 1 + allGroups.count) % allGroups.count
    }
    
    private func generateAllCombinations() {
        var combinations: [DemoGroup] = []
        
        // 获取每个类别的文件列表
        let armGestures = resourceFiles["arm_gesture"] ?? []
        let bodyGestures = resourceFiles["body_gesture"] ?? []
        let fingerGestures = resourceFiles["finger_gesture"] ?? []
        
        print("生成组合 - 文件列表：")
        print("手臂动作：\(armGestures)")
        print("身体动作：\(bodyGestures)")
        print("手指动作：\(fingerGestures)")
        
        // 生成所有可能的组合
        for arm in armGestures {
            for body in bodyGestures {
                for finger in fingerGestures {
                    combinations.append(DemoGroup(
                        armGesture: arm,
                        bodyGesture: body,
                        fingerGesture: finger
                    ))
                }
            }
        }
        
        print("生成的组合数量：\(combinations.count)")
        
        // 使用固定种子进行随机排序
        var generator = SeededRandomNumberGenerator(seed: shuffleSeed)
        allGroups = combinations.shuffled(using: &generator)
        currentGroupIndex = 0
        
        print("排序后的组合数量：\(allGroups.count)")
    }
    
    private func checkAndDownloadResources() async {
        isLoading = true
        defer { isLoading = false }
        
        // 检查OSS设置
        if settings.ossApiKey.isEmpty || settings.ossApiSecret.isEmpty {
            infoMessage = "请在手机设置中设置阿里云OSS相关设置"
            return
        }
        
        // 获取本地Documents目录
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            infoMessage = "无法访问本地存储"
            return
        }
        
        let demoPath = documentsPath.appendingPathComponent("DemoVideos")
        
        do {
            // 创建演示视频目录（如果不存在）
            if !FileManager.default.fileExists(atPath: demoPath.path) {
                try FileManager.default.createDirectory(at: demoPath, withIntermediateDirectories: true)
            }
            
            var stats: [String: Int] = [:]
            var files: [String: [String]] = [:]
            var needsUpdate = false
            
            for category in categories {
                let categoryPath = demoPath.appendingPathComponent(category)
                
                // 创建类别目录（如果不存在）
                if !FileManager.default.fileExists(atPath: categoryPath.path) {
                    try FileManager.default.createDirectory(at: categoryPath, withIntermediateDirectories: true)
                }
                
                // 获取云端文件列表
                infoMessage = "正在检查\(category)资源..."
                let cloudFiles = try await oss.listKeysWithPrefix(cloudPrefix + category)
                let cloudFileNames = Set(cloudFiles.map { url -> String in
                    let fullPath = URL(fileURLWithPath: url)
                    let fileName = fullPath.lastPathComponent
                    return fileName.components(separatedBy: ".").first ?? fileName
                })
                
                print("\(category) 云端文件：\(cloudFileNames)")
                
                // 获取本地文件列表
                var localFileNames = Set<String>()
                if let localFiles = try? FileManager.default.contentsOfDirectory(
                    at: categoryPath,
                    includingPropertiesForKeys: nil
                ) {
                    localFileNames = Set(localFiles.map { $0.deletingPathExtension().lastPathComponent })
                }
                
                print("\(category) 本地文件：\(localFileNames)")
                
                // 比较差异
                let filesToDelete = localFileNames.subtracting(cloudFileNames)
                let filesToDownload = cloudFileNames.subtracting(localFileNames)
                
                print("\(category) 需要删除：\(filesToDelete)")
                print("\(category) 需要下载：\(filesToDownload)")
                
                // 删除多余的本地文件
                for fileName in filesToDelete {
                    let fileURL = categoryPath.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                    needsUpdate = true
                }
                
                // 下载新文件
                if !filesToDownload.isEmpty {
                    infoMessage = "正在下载\(category)新资源..."
                    let success = try await oss.downloadFilesWithPrefix(
                        cloudPrefix + category,
                        rootDir: demoPath.path
                    )
                    if !success {
                        infoMessage = "下载\(category)资源失败"
                        return
                    }
                    needsUpdate = true
                }
                
                // 更新统计信息
                files[category] = Array(cloudFileNames).sorted()
                stats[category] = cloudFileNames.count
                
                print("\(category) 最终文件列表：\(files[category] ?? [])")
            }
            
            // 更新状态
            resourceStats = stats
            resourceFiles = files
            
            print("资源统计：\(stats)")
            print("文件列表：\(files)")
            
            // 总是重新生成组合（因为即使文件没变，也可能是第一次加载）
            generateAllCombinations()
            
            // 更新信息提示
            if !allGroups.isEmpty {
                infoMessage = needsUpdate ? "已更新资源并重新生成组合" : "资源已是最新"
            } else {
                infoMessage = "未能生成组合列表"
            }
            
        } catch {
            infoMessage = "资源检查/下载失败：\(error.localizedDescription)"
            print("错误：\(error)")
        }
    }
}

// 修改随机数生成器
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private let seed: UInt16
    private var current: UInt16
    
    init(seed: UInt16) {
        self.seed = seed
        self.current = seed
    }
    
    mutating func next() -> UInt64 {
        // 使用简单的线性同余生成器
        current = current &* 21_845 &+ 1
        // 转换为UInt64返回
        return UInt64(current)
    }
} 
