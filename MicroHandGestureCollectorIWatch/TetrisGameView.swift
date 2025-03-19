import SwiftUI

struct TetrisGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = TetrisGame()
    @StateObject private var bleService = BlePeripheralService.shared
    
    var body: some View {
        NavigationView {
            TetrisView(game: game)
                .navigationTitle("手势游戏")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") {
                            // 不再在这里停止蓝牙广播，只关闭游戏界面
                            dismiss()
                        }
                    }
                }
        }
    }
} 