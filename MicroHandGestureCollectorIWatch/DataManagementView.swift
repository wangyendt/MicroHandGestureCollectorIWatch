import SwiftUI
import UniformTypeIdentifiers
import ios_tools_lib

struct DataFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var isSelected: Bool = false
    var watchInfo: WatchInfo? // 添加手表信息
}

struct WatchInfo {
    let chipset: String
    let deviceSize: String
}

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dataFiles: [DataFile] = []
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingShareSheet = false
    @State private var selectedURLsToShare: [URL] = []
    @State private var isUploading = false
    @State private var showingUploadAlert = false
    @State private var uploadMessage = ""
    @State private var showingSettingsAlert = false
    
    // 从UserDefaults读取设置
    @AppStorage("ossEndpoint") private var ossEndpoint = "oss-cn-hangzhou.aliyuncs.com"
    @AppStorage("ossBucketName") private var ossBucketName = "wayne-data"
    @AppStorage("ossApiKey") private var ossApiKey = ""
    @AppStorage("ossApiSecret") private var ossApiSecret = ""
    @AppStorage("larkAppId") private var larkAppId = ""
    @AppStorage("larkAppSecret") private var larkAppSecret = ""
    @AppStorage("larkGroupName") private var larkGroupName = "测试群"
    
    private var oss: AliyunOSS {
        AliyunOSS(
            endpoint: ossEndpoint,
            bucketName: ossBucketName,
            apiKey: ossApiKey,
            apiSecret: ossApiSecret,
            verbose: true
        )
    }
    
    private var bot: LarkBot {
        LarkBot(
            appId: larkAppId,
            appSecret: larkAppSecret
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                if dataFiles.isEmpty {
                    Text("暂无数据文件")
                        .foregroundColor(.secondary)
                } else {
                    if isEditing {
                        // 全选/取消全选按钮
                        Button(action: {
                            if selectedFiles.count == dataFiles.count {
                                selectedFiles.removeAll()
                            } else {
                                selectedFiles = Set(dataFiles.map { $0.id })
                            }
                        }) {
                            HStack {
                                Image(systemName: selectedFiles.count == dataFiles.count ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedFiles.count == dataFiles.count ? .blue : .gray)
                                Text(selectedFiles.count == dataFiles.count ? "取消全选" : "全选")
                            }
                        }
                    }
                    
                    ForEach(dataFiles) { file in
                        HStack {
                            if isEditing {
                                Image(systemName: selectedFiles.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedFiles.contains(file.id) ? .blue : .gray)
                                    .onTapGesture {
                                        if selectedFiles.contains(file.id) {
                                            selectedFiles.remove(file.id)
                                        } else {
                                            selectedFiles.insert(file.id)
                                        }
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .font(.system(.body))
                                
                                HStack(spacing: 8) {
                                    if let fileSize = getFileSize(url: file.url) {
                                        Label(fileSize, systemImage: "folder.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let modificationDate = getFileModificationDate(url: file.url) {
                                        Label(modificationDate, systemImage: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if let watchInfo = file.watchInfo {
                                    HStack {
                                        Image(systemName: "applewatch")
                                        Text("\(watchInfo.chipset) \(watchInfo.deviceSize)")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("数据管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "完成" : "编辑") {
                        isEditing.toggle()
                        if !isEditing {
                            selectedFiles.removeAll()
                        }
                    }
                }
                if isEditing {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(selectedFiles.isEmpty)
                        
                        Spacer()
                        
                        Button {
                            if ossApiKey.isEmpty || ossApiSecret.isEmpty || larkAppId.isEmpty || larkAppSecret.isEmpty {
                                showingSettingsAlert = true
                            } else {
                                Task {
                                    await uploadToCloud()
                                }
                            }
                        } label: {
                            Label("上传", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(selectedFiles.isEmpty || isUploading)
                        
                        Spacer()
                        
                        Button {
                            prepareAndShare()
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedFiles.isEmpty)
                    }
                }
            }
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteSelectedFiles()
                }
            } message: {
                Text("确定要删除选中的\(selectedFiles.count)个文件吗？")
            }
            .alert("上传状态", isPresented: $showingUploadAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(uploadMessage)
            }
            .alert("设置缺失", isPresented: $showingSettingsAlert) {
                Button("取消", role: .cancel) { }
                Button("去设置") {
                    showWatchSettings()
                }
            } message: {
                Text("请先在设置中配置阿里云OSS和飞书机器人的API凭证")
            }
            .sheet(isPresented: $showingShareSheet, content: {
                if !selectedURLsToShare.isEmpty {
                    ShareSheet(activityItems: selectedURLsToShare)
                }
            })
            .overlay {
                if isUploading {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .overlay {
                            ProgressView("正在上传...")
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                        }
                }
            }
        }
        .onAppear {
            loadDataFiles()
        }
    }
    
    private func loadDataFiles() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let watchDataPath = documentsPath.appendingPathComponent("WatchData")
        
        do {
            // 确保 WatchData 文件夹存在
            if !FileManager.default.fileExists(atPath: watchDataPath.path) {
                try FileManager.default.createDirectory(at: watchDataPath, withIntermediateDirectories: true)
            }
            
            // 获取所有文件和文件夹
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: watchDataPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
            
            dataFiles = fileURLs.map { url in
                var dataFile = DataFile(name: url.lastPathComponent, url: url)
                if let watchInfo = readWatchInfo(from: url) {
                    dataFile.watchInfo = watchInfo
                }
                return dataFile
            }.sorted { $0.name > $1.name }
            
        } catch {
            print("加载文件出错: \(error)")
        }
    }
    
    private func readWatchInfo(from folderURL: URL) -> WatchInfo? {
        let infoURL = folderURL.appendingPathComponent("info.yaml")
        
        do {
            guard FileManager.default.fileExists(atPath: infoURL.path) else { return nil }
            
            let infoContent = try String(contentsOf: infoURL, encoding: .utf8)
            let lines = infoContent.components(separatedBy: .newlines)
            var isInDeviceSection = false
            var chipset = ""
            var deviceSize = ""
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                if trimmedLine == "device:" {
                    isInDeviceSection = true
                    continue
                }
                
                if isInDeviceSection {
                    if trimmedLine.hasPrefix("chipset:") {
                        chipset = trimmedLine.replacingOccurrences(of: "chipset:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmedLine.hasPrefix("deviceSize:") {
                        deviceSize = trimmedLine.replacingOccurrences(of: "deviceSize:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if !trimmedLine.hasPrefix("  ") && !trimmedLine.isEmpty {
                        isInDeviceSection = false
                    }
                }
            }
            
            if !chipset.isEmpty && !deviceSize.isEmpty {
                return WatchInfo(chipset: chipset, deviceSize: deviceSize)
            }
        } catch {
            print("读取info.yaml出错: \(error)")
        }
        return nil
    }
    
    private func deleteSelectedFiles() {
        for fileId in selectedFiles {
            if let file = dataFiles.first(where: { $0.id == fileId }) {
                do {
                    try FileManager.default.removeItem(at: file.url)
                } catch {
                    print("Error deleting file: \(error)")
                }
            }
        }
        loadDataFiles()
        selectedFiles.removeAll()
        isEditing = false
    }
    
    private func getFileSize(url: URL) -> String? {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if resources.isDirectory == true {
                return "文件夹"
            } else if let fileSize = resources.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            }
        } catch {
            print("Error getting file size: \(error)")
        }
        return nil
    }
    
    private func prepareAndShare() {
        selectedURLsToShare = dataFiles
            .filter { selectedFiles.contains($0.id) }
            .map { $0.url }
        
        // 确保有文件要分享
        if !selectedURLsToShare.isEmpty {
            showingShareSheet = true
        }
    }
    
    private func getFileModificationDate(url: URL) -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                return formatter.string(from: modificationDate)
            }
        } catch {
            print("Error getting file modification date: \(error)")
        }
        return nil
    }
    
    private func uploadToCloud() async {
        guard !selectedFiles.isEmpty else { return }
        
        isUploading = true
        var uploadedFolders: [String] = []
        
        do {
            for fileId in selectedFiles {
                if let file = dataFiles.first(where: { $0.id == fileId }) {
                    let success = try await oss.uploadDirectory(
                        localPath: file.url.path,
                        prefix: "micro_hand_gesture/raw_data/\(file.name)"
                    )
                    
                    if success {
                        uploadedFolders.append(file.name)
                    }
                }
            }
            
            // 发送飞书消息
            if !uploadedFolders.isEmpty {
                let message = "已上传\(uploadedFolders.count)条记录，分别为：\n" + uploadedFolders.joined(separator: "\n")
                let groupChatIds = try await bot.getGroupChatIdByName(larkGroupName)
                if let groupChatId = groupChatIds.first {
                    _ = try await bot.sendTextToChat(chatId: groupChatId, text: message)
                }
                
                uploadMessage = "上传成功！\n" + message
            } else {
                uploadMessage = "上传失败，请重试"
            }
        } catch {
            uploadMessage = "上传出错：\(error.localizedDescription)"
        }
        
        isUploading = false
        showingUploadAlert = true
    }
    
    private func showWatchSettings() {
        let settingsView = PhoneSettingsView()
        let hostingController = UIHostingController(rootView: settingsView)
        UIApplication.shared.windows.first?.rootViewController?.present(hostingController, animated: true)
    }
}

// 用于显示系统分享菜单的包装器
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // 添加完成回调
        controller.completionWithItemsHandler = { _, _, _, _ in
            // 关闭分享页面后的处理（如果需要）
        }
        
        // 在 iPad 上设置弹出位置（如果需要）
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.permittedArrowDirections = []
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 

