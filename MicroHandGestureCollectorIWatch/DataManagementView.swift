import SwiftUI
import UniformTypeIdentifiers
import ios_tools_lib

class DataManager: ObservableObject {
    @Published var dataFiles: [DataFile] = []
    
    func refreshDataFiles() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法获取文档路径")
            return
        }
        let watchDataPath = documentsPath.appendingPathComponent("WatchData")
        
        do {
            if !FileManager.default.fileExists(atPath: watchDataPath.path) {
                try FileManager.default.createDirectory(at: watchDataPath, withIntermediateDirectories: true)
            }
            
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
            var modelNumber = ""
            
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
                    } else if trimmedLine.hasPrefix("modelNumber:") {
                        modelNumber = trimmedLine.replacingOccurrences(of: "modelNumber:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmedLine == "collection:" {
                        isInDeviceSection = false
                    }
                }
            }
            
            if !chipset.isEmpty || !deviceSize.isEmpty || !modelNumber.isEmpty {
                return WatchInfo(
                    chipset: chipset,
                    deviceSize: deviceSize,
                    modelNumber: modelNumber
                )
            }
        } catch {
            print("读取info.yaml出错: \(error)")
        }
        return nil
    }
}

struct DataFileRow: View {
    let file: DataFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
                .font(.system(size: 14))
                .lineLimit(1)
            
            if let watchInfo = file.watchInfo {
                Text(watchInfo.displayText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

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
    @StateObject private var dataManager = DataManager()
    @State private var showingMissingFilesAlert = false
    @State private var missingFiles: [String] = []
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var isRefreshing = false
    @State private var showingProgressAlert = false
    @State private var progressMessage = ""
    
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
            VStack {
                List {
                    if dataManager.dataFiles.isEmpty {
                        Text("暂无数据文件")
                            .foregroundColor(.secondary)
                    } else {
                        if isEditing {
                            Button(action: {
                                if selectedFiles.count == dataManager.dataFiles.count {
                                    selectedFiles.removeAll()
                                } else {
                                    selectedFiles = Set(dataManager.dataFiles.map { $0.id })
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedFiles.count == dataManager.dataFiles.count ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFiles.count == dataManager.dataFiles.count ? .blue : .gray)
                                    Text(selectedFiles.count == dataManager.dataFiles.count ? "取消全选" : "全选")
                                }
                            }
                        }
                        
                        ForEach(dataManager.dataFiles) { file in
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
                                .contentShape(Rectangle())
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
                .refreshable {
                    isRefreshing = true
                    dataManager.refreshDataFiles()
                    isRefreshing = false
                }
                
                if !selectedFiles.isEmpty {
                    HStack {
                        Button(action: {
                            showingMissingFilesAlert = true
                            missingFiles = checkRequiredFiles()
                        }) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        
                        Button(action: {
                            syncSelectedFolders()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.green)
                        }
                        .padding()
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
                Text("确定要删除选中的\(selectedFiles.count)个文件夹吗？")
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
            .alert("缺失文件检查", isPresented: $showingMissingFilesAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(missingFiles.isEmpty ? "所选文件夹包含所有必需文件" : missingFiles.joined(separator: "\n"))
            }
            .alert("错误", isPresented: $showingErrorAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("处理中", isPresented: $showingProgressAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(progressMessage)
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
        dataManager.refreshDataFiles()  // 使用dataManager的刷新方法
    }
    
    private func deleteSelectedFiles() {
        for fileId in selectedFiles {
            if let file = dataManager.dataFiles.first(where: { $0.id == fileId }) {  // 使用dataManager.dataFiles
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
        selectedURLsToShare = dataManager.dataFiles  // 使用dataManager.dataFiles
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
            if let file = dataManager.dataFiles.first(where: { $0.id == fileId }) {
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
                if let file = dataManager.dataFiles.first(where: { $0.id == fileId }) {
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
    
    private func syncSelectedFolders() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logsPath = documentsPath.appendingPathComponent("Logs", isDirectory: true)
        let videosPath = documentsPath.appendingPathComponent("Videos", isDirectory: true)
        var successCount = 0
        var failedFolders: [String] = []
        
        for fileId in selectedFiles {
            if let file = dataManager.dataFiles.first(where: { $0.id == fileId }) {
                let folderName = file.name
                let logFileName = "\(folderName).log"
                let videoFileName = "\(folderName).mp4"
                let logFileURL = logsPath.appendingPathComponent(logFileName)
                let videoFileURL = videosPath.appendingPathComponent(videoFileName)
                
                let dataFolderURL = file.url
                let actionLogURL = dataFolderURL.appendingPathComponent("actions.log")
                let recordVideoURL = dataFolderURL.appendingPathComponent("record.mp4")
                let resultFileURL = dataFolderURL.appendingPathComponent("result.txt")
                let manualResultFileURL = dataFolderURL.appendingPathComponent("manual_result.txt")
                
                // 检查是否存在 result.txt
                guard FileManager.default.fileExists(atPath: resultFileURL.path) else {
                    print("未找到 result.txt")
                    failedFolders.append("\(folderName): 缺少 result.txt")
                    continue
                }
                
                // 如果数据文件夹中没有actions.log，但Logs文件夹中有对应的日志文件，则复制过来
                if !FileManager.default.fileExists(atPath: actionLogURL.path) && FileManager.default.fileExists(atPath: logFileURL.path) {
                    do {
                        try FileManager.default.copyItem(at: logFileURL, to: actionLogURL)
                        print("成功复制日志文件到数据文件夹：\(folderName)")
                    } catch {
                        print("复制日志文件失败：\(error)")
                        failedFolders.append("\(folderName): 复制日志文件失败")
                        continue
                    }
                }
                
                // 如果数据文件夹中没有record.mp4，但Videos文件夹中有对应的视频文件，则复制过来
                if !FileManager.default.fileExists(atPath: recordVideoURL.path) && FileManager.default.fileExists(atPath: videoFileURL.path) {
                    do {
                        try FileManager.default.copyItem(at: videoFileURL, to: recordVideoURL)
                        print("成功复制视频文件到数据文件夹：\(folderName)")
                    } catch {
                        print("复制视频文件失败：\(error)")
                        failedFolders.append("\(folderName): 复制视频文件失败")
                    }
                }
                
                // 检查是否存在日志文件（现在检查数据文件夹中的actions.log）
                guard FileManager.default.fileExists(atPath: actionLogURL.path) else {
                    print("未找到日志文件：\(folderName)")
                    failedFolders.append("\(folderName): 缺少日志文件")
                    continue
                }
                
                // 只在存在 manual_result.txt 时才进行备份
                if FileManager.default.fileExists(atPath: manualResultFileURL.path) {
                    let backupURL = dataFolderURL.appendingPathComponent("manual_result.txt.bak")
                    do {
                        if FileManager.default.fileExists(atPath: backupURL.path) {
                            try FileManager.default.removeItem(at: backupURL)
                        }
                        try FileManager.default.copyItem(at: manualResultFileURL, to: backupURL)
                    } catch {
                        print("备份 manual_result.txt 失败：\(error)")
                        failedFolders.append("\(folderName): 备份 manual_result.txt 失败")
                        continue
                    }
                }
                
                do {
                    // 读取 result.txt
                    let resultContent = try String(contentsOf: resultFileURL, encoding: .utf8)
                    let resultLines = resultContent.components(separatedBy: .newlines)
                    
                    // 读取日志文件（现在从actions.log读取）
                    let logContent = try String(contentsOf: actionLogURL, encoding: .utf8)
                    let logLines = logContent.components(separatedBy: .newlines)
                    
                    // 解析日志文件
                    var deletedIds = Set<String>()
                    var updatedTrueGestures: [String: String] = [:]
                    var updatedBodyGestures: [String: String] = [:]
                    var updatedArmGestures: [String: String] = [:]
                    var updatedFingerGestures: [String: String] = [:]
                    
                    for line in logLines.dropFirst() { // 跳过表头
                        let components = line.components(separatedBy: ",")
                        if components.count >= 3 {
                            let action = components[1]
                            let id = components[2]
                            
                            switch action {
                            case "D":
                                deletedIds.insert(id)
                            case "T":
                                if components.count >= 4 {
                                    updatedTrueGestures[id] = components[3]
                                }
                            case "G":
                                if components.count >= 6 {
                                    updatedBodyGestures[id] = components[3]
                                    updatedArmGestures[id] = components[4]
                                    updatedFingerGestures[id] = components[5]
                                }
                            default:
                                break
                            }
                        }
                    }
                    
                    // 创建新的 manual_result.txt
                    var manualResultContent = "timestamp_ns,relative_timestamp_s,gesture,confidence,peak_value,id,true_gesture,is_deleted,body_gesture,arm_gesture,finger_gesture\n"
                    
                    for line in resultLines.dropFirst() { // 跳过表头
                        if line.isEmpty { continue }
                        
                        let components = line.components(separatedBy: ",")
                        if components.count >= 6 {
                            let id = components[5]
                            let isDeleted = deletedIds.contains(id)
                            let predictedGesture = components[2]
                            let trueGesture = updatedTrueGestures[id] ?? predictedGesture
                            let bodyGesture = updatedBodyGestures[id] ?? "无"
                            let armGesture = updatedArmGestures[id] ?? "无"
                            let fingerGesture = updatedFingerGestures[id] ?? "无"
                            
                            manualResultContent += "\(components[0]),\(components[1]),\(components[2]),\(components[3]),\(components[4]),\(id),\(trueGesture),\(isDeleted ? "1" : "0"),\(bodyGesture),\(armGesture),\(fingerGesture)\n"
                        }
                    }
                    
                    // 写入新的 manual_result.txt
                    try manualResultContent.write(to: manualResultFileURL, atomically: true, encoding: .utf8)
                    print("成功更新 manual_result.txt：\(folderName)")
                    successCount += 1
                    
                } catch {
                    print("处理文件失败：\(error)")
                    failedFolders.append("\(folderName): \(error.localizedDescription)")
                }
            }
        }
        
        // 显示同步结果
        DispatchQueue.main.async {
            if failedFolders.isEmpty {
                self.progressMessage = "同步成功！\n成功处理 \(successCount) 个文件夹"
            } else {
                self.progressMessage = "同步完成\n成功：\(successCount) 个文件夹\n失败：\n" + failedFolders.joined(separator: "\n")
            }
            self.showingProgressAlert = true
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


