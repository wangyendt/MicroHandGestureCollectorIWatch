import SwiftUI
import WatchConnectivity

struct DataFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var isSelected: Bool = false
}

struct DataManagementView: View {
    @State private var dataFiles: [DataFile] = []
    @State private var isEditing = false
    @State private var isAllSelected = false
    @State private var showingDeleteAlert = false
    @State private var showingExportAlert = false
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("supervisorName") private var supervisorName: String = ""
    
    var selectedFiles: [DataFile] {
        dataFiles.filter { $0.isSelected }
    }
    
    private var showDeleteButton: Bool {
        return supervisorName != "陈科亦" && supervisorName != "徐森爱"
    }
    
    var body: some View {
        List {
            if dataFiles.isEmpty {
                Text("暂无数据")
                    .foregroundColor(.secondary)
            } else {
                if isEditing {
                    Button {
                        isAllSelected.toggle()
                        dataFiles = dataFiles.map { file in
                            var newFile = file
                            newFile.isSelected = isAllSelected
                            return newFile
                        }
                    } label: {
                        HStack {
                            Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isAllSelected ? .blue : .gray)
                            Text(isAllSelected ? "取消全选" : "全选")
                        }
                    }
                }
                
                ForEach($dataFiles) { $file in
                    HStack(alignment: .top) {
                        if isEditing {
                            Button {
                                file.isSelected.toggle()
                                updateAllSelectedState()
                            } label: {
                                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(file.isSelected ? .blue : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .font(.system(size: 14))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing.toggle()
                    if !isEditing {
                        resetSelection()
                    }
                } label: {
                    Text(isEditing ? "❌ 完成" : "✏️ 编辑")
                        .font(.system(size: 14))
                        .foregroundColor(isEditing ? .red : .blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ToolbarItemGroup(placement: .bottomBar) {
                if isEditing && !selectedFiles.isEmpty {
                    // 仅在特定监督者下显示删除按钮
                    if showDeleteButton {
                        Button {
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                            Text("删除")
                        }
                        .foregroundColor(.red)
                    }
                    
                    // 导出按钮始终可见（在编辑模式且有选中文件时）
                    Button {
                        showingExportAlert = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                        Text("导出")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackground(.clear, for: .bottomBar)
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedFiles()
            }
        } message: {
            Text("确定要删除选中的\(selectedFiles.count)个文件吗？")
        }
        .alert("确认导出", isPresented: $showingExportAlert) {
            Button("取消", role: .cancel) { }
            Button("导出", role: .none) {
                exportSelectedFiles()
            }
        } message: {
            Text("是否将选中的\(selectedFiles.count)个文件导出到iPhone？")
        }
        .onAppear {
            loadDataFiles()
        }
        
        if connectivityManager.isSending {
            ProgressView("正在导出...")
                .padding()
        } else if !connectivityManager.lastMessage.isEmpty {
            Text(connectivityManager.lastMessage)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
        }
    }
    
    private func resetSelection() {
        isAllSelected = false
        dataFiles = dataFiles.map { file in
            var newFile = file
            newFile.isSelected = false
            return newFile
        }
    }
    
    private func updateAllSelectedState() {
        isAllSelected = !dataFiles.contains { !$0.isSelected }
    }
    
    private func loadDataFiles() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            dataFiles = fileURLs
                .filter { url in
                    let filename = url.lastPathComponent
                    return filename.contains("_右手_") || filename.contains("_左手_")
                }
                .map { DataFile(name: $0.lastPathComponent, url: $0) }
                .sorted { $0.name > $1.name }
        } catch {
            print("Error loading files: \(error)")
        }
    }
    
    private func deleteSelectedFiles() {
        for file in selectedFiles {
            do {
                try FileManager.default.removeItem(at: file.url)
            } catch {
                print("Error deleting file: \(error)")
            }
        }
        loadDataFiles()
        isEditing = false
    }
    
    private func exportSelectedFiles() {
        let urls = selectedFiles.map { $0.url }
        connectivityManager.sendDataToPhone(fileURLs: urls)
    }
} 
