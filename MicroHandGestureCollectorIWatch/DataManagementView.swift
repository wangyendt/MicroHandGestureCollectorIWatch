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
    let modelNumber: String
    
    var displayText: String {
        var components: [String] = []
        if !chipset.isEmpty { components.append(chipset) }
        if !deviceSize.isEmpty { components.append(deviceSize) }
        if !modelNumber.isEmpty { components.append("(\(modelNumber))") }
        return components.joined(separator: " ")
    }
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
    @State private var selectedDataFile: DataFile?
    @State private var showingDetailView = false
    @State private var showingRenameAlert = false
    @State private var newFileName = ""
    @State private var fileToRename: DataFile?
    
    @ObservedObject private var settings = AppSettings.shared
    
    private var oss: AliyunOSS {
        AliyunOSS(
            endpoint: settings.ossEndpoint,
            bucketName: settings.ossBucketName,
            apiKey: settings.ossApiKey,
            apiSecret: settings.ossApiSecret,
            verbose: true
        )
    }
    
    private var bot: LarkBot {
        LarkBot(
            appId: settings.larkAppId,
            appSecret: settings.larkAppSecret
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
                                        Text(watchInfo.displayText)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())  // 确保整个区域可点击
                            .onTapGesture {
                                if !isEditing {
                                    selectedDataFile = file
                                    showingDetailView = true
                                }
                            }
                            .contextMenu {
                                Button(action: {
                                    fileToRename = file
                                    newFileName = file.name
                                    showingRenameAlert = true
                                }) {
                                    Label("重命名", systemImage: "pencil")
                                }
                            }
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
                            if settings.ossApiKey.isEmpty || settings.ossApiSecret.isEmpty || settings.larkAppId.isEmpty || settings.larkAppSecret.isEmpty {
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
            .alert("重命名文件夹", isPresented: $showingRenameAlert) {
                TextField("新文件名", text: $newFileName)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let file = fileToRename {
                        renameFile(file)
                    }
                }
            } message: {
                Text("请输入新的文件名")
            }
            .sheet(isPresented: $showingShareSheet, content: {
                if !selectedURLsToShare.isEmpty {
                    ShareSheet(activityItems: selectedURLsToShare)
                }
            })
            .sheet(isPresented: $showingDetailView) {
                if let dataFile = selectedDataFile {
                    DataDetailView(dataFile: dataFile)
                }
            }
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
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法获取文档路径")
            return
        }
        let watchDataPath = documentsPath.appendingPathComponent("WatchData")
        print("WatchData路径：\(watchDataPath.path)")
        
        do {
            // 确保 WatchData 文件夹存在
            if !FileManager.default.fileExists(atPath: watchDataPath.path) {
                try FileManager.default.createDirectory(at: watchDataPath, withIntermediateDirectories: true)
                print("创建WatchData文件夹")
            }
            
            // 获取所有文件和文件夹
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: watchDataPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
            print("找到\(fileURLs.count)个文件/文件夹")
            
            dataFiles = fileURLs.map { url in
                print("\n处理文件：\(url.lastPathComponent)")
                var dataFile = DataFile(name: url.lastPathComponent, url: url)
                if let watchInfo = readWatchInfo(from: url) {
                    print("成功读取设备信息：\(watchInfo.displayText)")
                    dataFile.watchInfo = watchInfo
                } else {
                    print("未能读取设备信息")
                }
                return dataFile
            }.sorted { $0.name > $1.name }
            
            print("总共处理了\(dataFiles.count)个文件")
            
        } catch {
            print("加载文件出错: \(error)")
        }
    }
    
    private func readWatchInfo(from folderURL: URL) -> WatchInfo? {
        let infoURL = folderURL.appendingPathComponent("info.yaml")
        print("准备读取文件：\(infoURL.path)")
        
        do {
            guard FileManager.default.fileExists(atPath: infoURL.path) else {
                print("文件不存在：\(infoURL.path)")
                return nil
            }
            
            let infoContent = try String(contentsOf: infoURL, encoding: .utf8)
            print("成功读取文件内容，长度：\(infoContent.count)字节")
            
            let lines = infoContent.components(separatedBy: .newlines)
            print("文件总行数：\(lines.count)")
            print("文件内容：\n\(infoContent)")
            
            var isInDeviceSection = false
            var chipset = ""
            var deviceSize = ""
            var modelNumber = ""
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                if trimmedLine == "device:" {
                    print("找到设备部分")
                    isInDeviceSection = true
                    continue
                }
                
                if isInDeviceSection {
                    if trimmedLine.hasPrefix("chipset:") {
                        chipset = trimmedLine.replacingOccurrences(of: "chipset:", with: "").trimmingCharacters(in: .whitespaces)
                        print("读取到芯片：\(chipset)")
                    } else if trimmedLine.hasPrefix("deviceSize:") {
                        deviceSize = trimmedLine.replacingOccurrences(of: "deviceSize:", with: "").trimmingCharacters(in: .whitespaces)
                        print("读取到尺寸：\(deviceSize)")
                    } else if trimmedLine.hasPrefix("modelNumber:") {
                        modelNumber = trimmedLine.replacingOccurrences(of: "modelNumber:", with: "").trimmingCharacters(in: .whitespaces)
                        print("读取到型号：\(modelNumber)")
                    } else if trimmedLine == "collection:" {
                        print("遇到collection部分，退出设备部分解析")
                        isInDeviceSection = false
                    }
                }
            }
            
            print("最终结果 - 芯片：[\(chipset)] 尺寸：[\(deviceSize)] 型号：[\(modelNumber)]")
            
            // 只要至少有一个字段不为空就创建 WatchInfo
            if !chipset.isEmpty || !deviceSize.isEmpty || !modelNumber.isEmpty {
                let watchInfo = WatchInfo(
                    chipset: chipset,
                    deviceSize: deviceSize,
                    modelNumber: modelNumber
                )
                print("创建 WatchInfo 成功：\(watchInfo.displayText)")
                return watchInfo
            } else {
                print("所有字段都为空，返回 nil")
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
    
    private func checkRequiredFiles() -> [String] {
        let requiredFiles = ["acc.txt", "gyro.txt", "info.yaml", "manual_result.txt", "statistics.yaml", "result.txt"]
        var missingFilesInFolders: [String] = []
        
        for fileId in selectedFiles {
            if let file = dataFiles.first(where: { $0.id == fileId }) {
                let missingFiles = requiredFiles.filter { fileName in
                    !FileManager.default.fileExists(atPath: file.url.appendingPathComponent(fileName).path)
                }
                
                if !missingFiles.isEmpty {
                    missingFilesInFolders.append("\(file.name): 缺少 \(missingFiles.joined(separator: ", "))")
                }
            }
        }
        
        return missingFilesInFolders
    }
    
    private func uploadToCloud() async {
        guard !selectedFiles.isEmpty else { return }
        
        // 首先检查文件完整性
        let missingFilesInFolders = checkRequiredFiles()
        if !missingFilesInFolders.isEmpty {
            DispatchQueue.main.async {
                self.uploadMessage = "以下文件夹缺少必需文件：\n\n" + missingFilesInFolders.joined(separator: "\n")
                self.showingUploadAlert = true
            }
            return
        }
        
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
                let groupChatIds = try await bot.getGroupChatIdByName(settings.larkGroupName)
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
    
    private func renameFile(_ file: DataFile) {
        let fileManager = FileManager.default
        let oldPath = file.url
        let newPath = oldPath.deletingLastPathComponent().appendingPathComponent(newFileName)
        
        do {
            try fileManager.moveItem(at: oldPath, to: newPath)
            loadDataFiles() // 重新加载文件列表
        } catch {
            print("重命名失败: \(error)")
        }
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

