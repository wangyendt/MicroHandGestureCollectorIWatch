import SwiftUI
import UniformTypeIdentifiers

struct DataFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var isSelected: Bool = false
}

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dataFiles: [DataFile] = []
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingShareSheet = false
    @State private var selectedURLsToShare: [URL] = []
    
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
                            VStack(alignment: .leading) {
                                Text(file.name)
                                    .lineLimit(1)
                                if let fileSize = getFileSize(url: file.url) {
                                    Text(fileSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                            selectedURLsToShare = dataFiles
                                .filter { selectedFiles.contains($0.id) }
                                .map { $0.url }
                            showingShareSheet = true
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
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: selectedURLsToShare)
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
                DataFile(name: url.lastPathComponent, url: url)
            }.sorted { $0.name > $1.name }
            
        } catch {
            print("Error loading files: \(error)")
        }
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
}

// 用于显示系统分享菜单的包装器
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 