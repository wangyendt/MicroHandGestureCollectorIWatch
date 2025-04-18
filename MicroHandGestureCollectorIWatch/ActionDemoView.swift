import SwiftUI
import AVKit
import ios_tools_lib

struct DemoGroup: Identifiable, Equatable {
    let id = UUID()
    let armGesture: String
    let bodyGesture: String
    let fingerGesture: String
    
    static func == (lhs: DemoGroup, rhs: DemoGroup) -> Bool {
        return lhs.armGesture == rhs.armGesture &&
               lhs.bodyGesture == rhs.bodyGesture &&
               lhs.fingerGesture == rhs.fingerGesture
    }
}

struct ActionDemoView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var sensorManager = SensorDataManager.shared
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
    @State private var showingGestureSettings = false
    
    // 添加资源URL状态
    @State private var currentArmVideoURL: URL?
    @State private var currentBodyImageURL: URL?
    @State private var currentFingerVideoURL: URL?
    @State private var videoPlayer: AVPlayer?
    @State private var fingerVideoPlayer: AVPlayer?
    
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
            // 动作演示标题和按钮
            HStack {
                Text("当前组合")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showingGestureSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(isLoading)
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
                    HStack(spacing: 20) {
                        Text("第 \(currentGroupIndex + 1)/\(allGroups.count) 组")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                        
                        Text("种子：\(shuffleSeed)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                    
                    Text("手臂\(resourceStats["arm_gesture"] ?? 0)个 · 身体\(resourceStats["body_gesture"] ?? 0)个 · 手指\(resourceStats["finger_gesture"] ?? 0)个")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    // 资源显示区域
                    VStack(spacing: 15) {
                        // 手臂动作视频
                        VStack(spacing: 5) {
                            if let videoURL = currentArmVideoURL {
                                VideoPlayer(player: videoPlayer)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .cornerRadius(10)
                                    .onChange(of: videoURL) { newURL in
                                        // 当URL改变时，重新创建播放器
                                        videoPlayer?.pause()
                                        NotificationCenter.default.removeObserver(self)
                                        videoPlayer = AVPlayer(url: newURL)
                                        videoPlayer?.actionAtItemEnd = .none
                                        videoPlayer?.play()
                                        
                                        // 重新添加循环播放观察者
                                        NotificationCenter.default.addObserver(
                                            forName: .AVPlayerItemDidPlayToEndTime,
                                            object: videoPlayer?.currentItem,
                                            queue: .main
                                        ) { _ in
                                            videoPlayer?.seek(to: .zero)
                                            videoPlayer?.play()
                                        }
                                    }
                                    .onAppear {
                                        videoPlayer = AVPlayer(url: videoURL)
                                        videoPlayer?.actionAtItemEnd = .none
                                        videoPlayer?.play()
                                        
                                        // 添加循环播放观察者
                                        NotificationCenter.default.addObserver(
                                            forName: .AVPlayerItemDidPlayToEndTime,
                                            object: videoPlayer?.currentItem,
                                            queue: .main
                                        ) { _ in
                                            videoPlayer?.seek(to: .zero)
                                            videoPlayer?.play()
                                        }
                                    }
                                    .onDisappear {
                                        videoPlayer?.pause()
                                        NotificationCenter.default.removeObserver(self)
                                        videoPlayer = nil
                                    }
                            }
                            Text("手臂动作：\(group.armGesture)")
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                        }
                        
                        HStack(spacing: 15) {
                            // 身体动作图片
                            VStack(spacing: 5) {
                                if let imageURL = currentBodyImageURL {
                                    AsyncImage(url: imageURL) { image in
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 150)
                                    .cornerRadius(10)
                                }
                                Text("身体动作：\(group.bodyGesture)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                            }
                            
                            // 手指动作视频
                            VStack(spacing: 5) {
                                if let videoURL = currentFingerVideoURL {
                                    VideoPlayer(player: fingerVideoPlayer)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 150)
                                        .cornerRadius(10)
                                        .onChange(of: videoURL) { newURL in
                                            // 当URL改变时，重新创建播放器
                                            fingerVideoPlayer?.pause()
                                            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: fingerVideoPlayer?.currentItem)
                                            fingerVideoPlayer = AVPlayer(url: newURL)
                                            fingerVideoPlayer?.actionAtItemEnd = .none
                                            fingerVideoPlayer?.play()
                                            
                                            // 重新添加循环播放观察者
                                            NotificationCenter.default.addObserver(
                                                forName: .AVPlayerItemDidPlayToEndTime,
                                                object: fingerVideoPlayer?.currentItem,
                                                queue: .main
                                            ) { _ in
                                                fingerVideoPlayer?.seek(to: .zero)
                                                fingerVideoPlayer?.play()
                                            }
                                        }
                                        .onAppear {
                                            fingerVideoPlayer = AVPlayer(url: videoURL)
                                            fingerVideoPlayer?.actionAtItemEnd = .none
                                            fingerVideoPlayer?.play()
                                            
                                            // 添加循环播放观察者
                                            NotificationCenter.default.addObserver(
                                                forName: .AVPlayerItemDidPlayToEndTime,
                                                object: fingerVideoPlayer?.currentItem,
                                                queue: .main
                                            ) { _ in
                                                fingerVideoPlayer?.seek(to: .zero)
                                                fingerVideoPlayer?.play()
                                            }
                                        }
                                        .onDisappear {
                                            fingerVideoPlayer?.pause()
                                            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: fingerVideoPlayer?.currentItem)
                                            fingerVideoPlayer = nil
                                        }
                                }
                                Text("手指动作：\(group.fingerGesture)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
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
        .onChange(of: currentGroup) { newGroup in
            if let group = newGroup {
                updateResourceURLs(for: group)
            }
        }
        .sheet(isPresented: $showingGestureSettings) {
            GestureSettingsView(resourceFiles: resourceFiles, onSave: {
                // 重新生成组合
                generateAllCombinations()
                // 更新当前组的资源URL
                if let group = currentGroup {
                    updateResourceURLs(for: group)
                }
            })
        }
    }
    
    private func showNextGroup() {
        guard !allGroups.isEmpty else { return }
        currentGroupIndex = (currentGroupIndex + 1) % allGroups.count
        if let group = currentGroup {
            updateResourceURLs(for: group)
        }
    }
    
    private func showPreviousGroup() {
        guard !allGroups.isEmpty else { return }
        currentGroupIndex = (currentGroupIndex - 1 + allGroups.count) % allGroups.count
        if let group = currentGroup {
            updateResourceURLs(for: group)
        }
    }
    
    private func generateAllCombinations() {
        var combinations: [DemoGroup] = []
        
        // 1. 获取每个类别的动作列表
        let armGestures = resourceFiles["arm_gesture"] ?? []
        let bodyGestures = resourceFiles["body_gesture"] ?? []
        let fingerGestures = resourceFiles["finger_gesture"] ?? []
        
        print("生成组合 - 文件列表：")
        print("手臂动作：\(armGestures)")
        print("身体动作：\(bodyGestures)")
        print("手指动作：\(fingerGestures)")
        
        // 2. 获取动作映射关系
        let bodyArmMapping = settings.gestureMapping
        let armFingerMapping = settings.armFingerMapping
        
        // 3. 先将身体动作随机排序
        var generator = SeededRandomNumberGenerator(seed: shuffleSeed)
        let shuffledBodyGestures = bodyGestures.shuffled(using: &generator)
        
        // 4. 对每个身体动作，生成并随机排序其对应的手臂x手指组合
        for body in shuffledBodyGestures {
            var bodyGroupCombinations: [DemoGroup] = []
            
            // 获取该身体动作对应的手臂动作列表
            let validArmGestures = bodyArmMapping[body] ?? Set(armGestures)
            
            // 如果没有配置映射关系，或者该身体动作被选中
            if bodyArmMapping.isEmpty || bodyArmMapping.keys.contains(body) {
                // 生成该身体动作下的所有有效手臂x手指组合
                for arm in validArmGestures {
                    // 获取该手臂动作对应的手指动作列表
                    let validFingerGestures = armFingerMapping[arm] ?? Set(fingerGestures)
                    
                    // 如果没有配置手臂-手指映射关系，或者该手臂动作被选中
                    if armFingerMapping.isEmpty || armFingerMapping.keys.contains(arm) {
                        for finger in validFingerGestures {
                            bodyGroupCombinations.append(DemoGroup(
                                armGesture: arm,
                                bodyGesture: body,
                                fingerGesture: finger
                            ))
                        }
                    }
                }
                
                // 随机打乱该身体动作下的所有组合
                bodyGroupCombinations.shuffle(using: &generator)
                
                // 将该身体动作的所有组合添加到最终结果中
                combinations.append(contentsOf: bodyGroupCombinations)
            }
        }
        
        print("生成的组合数量：\(combinations.count)")
        allGroups = combinations
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
            var resourcesChanged = false
            
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
                    // 删除所有可能的文件扩展名
                    for ext in ["mp4", "mov", "png"] {
                        let fileURL = categoryPath.appendingPathComponent("\(fileName).\(ext)")
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            try FileManager.default.removeItem(at: fileURL)
                            resourcesChanged = true
                        }
                    }
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
                    
                    // 移动文件到正确的目录
                    let tempPath = demoPath.appendingPathComponent(cloudPrefix + category)
                    if FileManager.default.fileExists(atPath: tempPath.path) {
                        let tempContents = try FileManager.default.contentsOfDirectory(
                            at: tempPath,
                            includingPropertiesForKeys: nil
                        )
                        for fileURL in tempContents {
                            let fileName = fileURL.lastPathComponent
                            let destinationURL = categoryPath.appendingPathComponent(fileName)
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }
                            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                            resourcesChanged = true
                        }
                        // 清理临时目录
                        try FileManager.default.removeItem(at: tempPath)
                    }
                    
                    needsUpdate = true
                }
                
                // 检查本地文件的完整性
                let currentLocalFiles = try FileManager.default.contentsOfDirectory(
                    at: categoryPath,
                    includingPropertiesForKeys: [.fileSizeKey]
                )
                
                for fileURL in currentLocalFiles {
                    let resources = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resources.fileSize, fileSize == 0 {
                        // 删除大小为0的文件
                        try FileManager.default.removeItem(at: fileURL)
                        resourcesChanged = true
                        needsUpdate = true
                    }
                }
                
                // 更新统计信息
                let finalLocalFiles = try FileManager.default.contentsOfDirectory(
                    at: categoryPath,
                    includingPropertiesForKeys: nil
                )
                let finalFileNames = Set(finalLocalFiles.map { $0.deletingPathExtension().lastPathComponent })
                files[category] = Array(finalFileNames).sorted()
                stats[category] = finalFileNames.count
                
                print("\(category) 最终文件列表：\(files[category] ?? [])")
            }
            
            // 更新状态
            resourceStats = stats
            resourceFiles = files
            
            print("资源统计：\(stats)")
            print("文件列表：\(files)")
            
            // 如果资源发生变化，检查并更新设置
            if resourcesChanged {
                if let armGestures = files["arm_gesture"],
                   let fingerGestures = files["finger_gesture"] {
                    
                    // 检查是否有新增的手臂动作
                    for armGesture in armGestures {
                        if settings.armFingerMapping[armGesture] == nil {
                            // 只为新增的手臂动作设置默认的手指动作映射
                            settings.armFingerMapping[armGesture] = Set(fingerGestures)
                        }
                    }
                    
                    // 移除不存在的手臂动作的映射
                    settings.armFingerMapping = settings.armFingerMapping.filter { armGestures.contains($0.key) }
                }
                
                if let bodyGestures = files["body_gesture"],
                   let armGestures = files["arm_gesture"] {
                    
                    // 检查是否有新增的身体动作
                    for bodyGesture in bodyGestures {
                        if settings.gestureMapping[bodyGesture] == nil {
                            // 只为新增的身体动作设置默认的手臂动作映射
                            settings.gestureMapping[bodyGesture] = Set(armGestures)
                        }
                    }
                    
                    // 移除不存在的身体动作的映射
                    settings.gestureMapping = settings.gestureMapping.filter { bodyGestures.contains($0.key) }
                    
                    // 确保每个身体动作的手臂动作列表中不包含已经不存在的手臂动作
                    for bodyGesture in bodyGestures {
                        if let armMappings = settings.gestureMapping[bodyGesture] {
                            settings.gestureMapping[bodyGesture] = armMappings.filter { armGestures.contains($0) }
                        }
                    }
                }
            }
            
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
    
    private func updateResourceURLs(for group: DemoGroup) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let demoPath = documentsPath.appendingPathComponent("DemoVideos")
        
        // 更新手臂动作视频URL
        let armPath = demoPath.appendingPathComponent("arm_gesture")
        let armBaseName = group.armGesture
        if let videoURL = findVideoFile(in: armPath, baseName: armBaseName) {
            print("找到手臂动作视频: \(videoURL.path)")
            currentArmVideoURL = videoURL
        } else {
            print("未找到手臂动作视频，路径: \(armPath.path), 基础名: \(armBaseName)")
        }
        
        // 更新身体动作图片URL
        let bodyPath = demoPath.appendingPathComponent("body_gesture")
        let bodyImageURL = bodyPath.appendingPathComponent(group.bodyGesture + ".png")
        print("设置身体动作图片: \(bodyImageURL.path)")
        currentBodyImageURL = bodyImageURL
        
        // 更新手指动作视频 URL
        let fingerPath = demoPath.appendingPathComponent("finger_gesture")
        let fingerBaseName = group.fingerGesture
        if let videoURL = findVideoFile(in: fingerPath, baseName: fingerBaseName) {
            print("找到手指动作视频: \(videoURL.path)")
            currentFingerVideoURL = videoURL
        } else {
            print("未找到手指动作视频，路径: \(fingerPath.path), 基础名: \(fingerBaseName)")
        }
        
        // 更新 SensorDataManager 中的当前动作状态
        sensorManager.updateCurrentGestures(
            body: group.bodyGesture,
            arm: group.armGesture,
            finger: group.fingerGesture
        )
    }
    
    private func findVideoFile(in directory: URL, baseName: String) -> URL? {
        // 检查mp4
        let mp4URL = directory.appendingPathComponent(baseName + ".mp4")
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            print("找到MP4文件: \(mp4URL.path)")
            return mp4URL
        }
        
        // 检查mov
        let movURL = directory.appendingPathComponent(baseName + ".mov")
        if FileManager.default.fileExists(atPath: movURL.path) {
            print("找到MOV文件: \(movURL.path)")
            return movURL
        }
        
        print("在目录 \(directory.path) 中未找到视频文件，基础名: \(baseName)")
        return nil
    }
}

// 修改随机数生成器
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private let multiplier: UInt64 = 6364136223846793005
    private let increment: UInt64 = 1442695040888963407
    private var state: UInt64
    
    init(seed: UInt16) {
        self.state = UInt64(seed)
        _ = next() // 丢弃第一个值以改善随机性
    }
    
    mutating func next() -> UInt64 {
        state = state &* multiplier &+ increment
        return state
    }
}

// 修改 GIF 显示组件
struct GIFImage: UIViewRepresentable {
    let url: URL
    @State private var imageView = UIImageView()
    
    func makeUIView(context: Context) -> UIImageView {
        imageView.contentMode = .scaleAspectFit
        loadGIF()
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        loadGIF()
    }
    
    private func loadGIF() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url),
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                let frameCount = CGImageSourceGetCount(source)
                var images: [UIImage] = []
                var delays: [Double] = []
                
                for i in 0..<frameCount {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                        images.append(UIImage(cgImage: cgImage))
                        
                        if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                           let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                            var delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
                            if delay < 0.011 { delay = 0.1 }
                            delays.append(delay)
                        }
                    }
                }
                
                let totalDuration = delays.reduce(0, +)
                
                DispatchQueue.main.async {
                    imageView.stopAnimating()
                    imageView.animationImages = images
                    imageView.animationDuration = totalDuration
                    imageView.animationRepeatCount = 0
                    imageView.startAnimating()
                }
            }
        }
    }
} 
