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
                            bleService.stopAdvertising()
                            dismiss()
                        }
                    }
                }
        }
        .onAppear {
            bleService.startAdvertising()
        }
        .onDisappear {
            bleService.stopAdvertising()
        }
    }
} 