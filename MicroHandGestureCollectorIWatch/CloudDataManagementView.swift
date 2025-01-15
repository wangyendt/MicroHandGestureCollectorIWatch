import SwiftUI
import ios_tools_lib

struct CloudDataFile: Identifiable {
    let id = UUID()
    let name: String
    var isSelected: Bool = false
}

struct CloudDataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dataFiles: [CloudDataFile] = []
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingShareSheet = false
    @State private var selectedURLsToShare: [URL] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var isUploading = false
    @State private var showingUploadAlert = false
    @State private var uploadMessage = ""
    @State private var showingSettingsAlert = false
    
    @ObservedObject private var settings = AppSettings.shared
    
    private let cloudPrefix = "micro_hand_gesture/raw_data/"
    
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
            ZStack {
                List {
                    if dataFiles.isEmpty && !isLoading {
                        Text("暂无云端数据")
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
                                
                                Text(file.name)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .font(.system(.body))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .refreshable {
                    await loadCloudData()
                }
                
                if isLoading {
                    ProgressView("加载中...")
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .navigationTitle("云端数据管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !dataFiles.isEmpty {
                        Button(isEditing ? "完成" : "编辑") {
                            isEditing.toggle()
                            if !isEditing {
                                selectedFiles.removeAll()
                            }
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(selectedFiles.isEmpty)
                    }
                }
            }
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    Task {
                        await deleteSelectedFiles()
                    }
                }
            } message: {
                Text("确定要删除选中的\(selectedFiles.count)个文件吗？此操作不可恢复。")
            }
            .alert("错误", isPresented: $showingErrorAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .task {
            await loadCloudData()
        }
    }
    
    private func loadCloudData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let keys = try await oss.listKeysWithPrefix(cloudPrefix)
            print("获取到的keys: \(keys)") // 添加调试输出
            
            // 提取文件夹名称（去掉前缀和后面的文件路径）
            let folders = Set(keys.compactMap { key -> String? in
                // 移除前缀
                let path = key.replacingOccurrences(of: cloudPrefix, with: "")
                // 获取第一级目录名
                let components = path.components(separatedBy: "/")
                guard let firstComponent = components.first, !firstComponent.isEmpty else {
                    return nil
                }
                return firstComponent
            })
            
            print("提取的文件夹: \(folders)") // 添加调试输出
            
            DispatchQueue.main.async {
                dataFiles = folders.map { CloudDataFile(name: $0) }.sorted { $0.name > $1.name }
                print("数据文件数量: \(dataFiles.count)") // 添加调试输出
            }
        } catch {
            print("加载出错: \(error)") // 添加调试输出
            DispatchQueue.main.async {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
    
    private func deleteSelectedFiles() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            for fileId in selectedFiles {
                if let file = dataFiles.first(where: { $0.id == fileId }) {
                    let prefix = cloudPrefix + file.name
                    _ = try await oss.deleteFilesWithPrefix(prefix)
                }
            }
            
            // 重新加载数据
            await loadCloudData()
            
            // 退出编辑模式
            DispatchQueue.main.async {
                isEditing = false
                selectedFiles.removeAll()
            }
        } catch {
            DispatchQueue.main.async {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
} 
