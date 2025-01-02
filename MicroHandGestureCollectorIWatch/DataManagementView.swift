import SwiftUI

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
    
    var body: some View {
        NavigationView {
            List {
                if dataFiles.isEmpty {
                    Text("暂无数据文件")
                        .foregroundColor(.secondary)
                } else {
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
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .disabled(selectedFiles.isEmpty)
                            
                            Spacer()
                            
                            Button {
                                // 导出选中的文件
                                let selectedURLs = dataFiles
                                    .filter { selectedFiles.contains($0.id) }
                                    .map { $0.url }
                                // 调用导出方法
                            } label: {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                            .disabled(selectedFiles.isEmpty)
                        }
                    }
                }
            }
            .alert("确认删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteSelectedFiles()
                }
            } message: {
                Text("确定要删除选中的文件吗？")
            }
        }
        .onAppear {
            loadDataFiles()
        }
    }
    
    private func loadDataFiles() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            dataFiles = fileURLs
                .filter { $0.pathExtension == "txt" }
                .map { DataFile(name: $0.lastPathComponent, url: $0) }
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
} 