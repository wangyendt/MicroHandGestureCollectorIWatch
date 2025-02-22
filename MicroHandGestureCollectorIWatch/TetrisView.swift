import SwiftUI

struct TetrisView: View {
    @ObservedObject var game: TetrisGame
    @ObservedObject var bleService = BlePeripheralService.shared
    @State private var timer: Timer?
    @State private var isGameRunning = false
    
    private let blockSize: CGFloat = UIScreen.main.bounds.width * 0.042
    private let gameSpeed: TimeInterval = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                // 游戏主区域
                VStack {
                    // 状态栏
                    HStack {
                        Text("已\(bleService.isConnected ? "连接" : "断开")")
                            .foregroundColor(bleService.isConnected ? .green : .red)
                        Spacer()
                        Text("计数: \(bleService.currentValue)")
                    }
                    .padding(.horizontal)
                    
                    // 游戏区域
                    ZStack {
                        // 背景网格
                        VStack(spacing: 1) {
                            ForEach(0..<TetrisGame.ROWS, id: \.self) { _ in
                                HStack(spacing: 1) {
                                    ForEach(0..<TetrisGame.COLS, id: \.self) { _ in
                                        Color.black
                                            .frame(width: blockSize, height: blockSize)
                                            .border(Color.gray, width: 0.5)
                                    }
                                }
                            }
                        }
                        
                        // 已固定的方块
                        ForEach(0..<TetrisGame.ROWS, id: \.self) { row in
                            ForEach(0..<TetrisGame.COLS, id: \.self) { col in
                                if let color = game.board[row][col] {
                                    color
                                        .frame(width: blockSize - 1, height: blockSize - 1)
                                        .position(
                                            x: CGFloat(col) * blockSize + blockSize/2,
                                            y: CGFloat(row) * blockSize + blockSize/2
                                        )
                                }
                            }
                        }
                        
                        // 当前方块
                        ForEach(0..<game.currentShape.count, id: \.self) { row in
                            ForEach(0..<game.currentShape[0].count, id: \.self) { col in
                                if game.currentShape[row][col] == 1 {
                                    game.currentColor
                                        .frame(width: blockSize - 1, height: blockSize - 1)
                                        .position(
                                            x: CGFloat(game.currentCol + col) * blockSize + blockSize/2,
                                            y: CGFloat(game.currentRow + row) * blockSize + blockSize/2
                                        )
                                }
                            }
                        }
                        
                        // 游戏结束提示
                        if game.isGameOver {
                            VStack {
                                Text("游戏结束!")
                                    .font(.title)
                                    .foregroundColor(.red)
                                Button("重新开始") {
                                    restartGame()
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                
                // 右侧信息区
                VStack {
                    // 下一个方块预览
                    VStack {
                        Text("下一个:")
                            .font(.headline)
                        ZStack {
                            Color.black
                                .frame(width: blockSize * 4, height: blockSize * 4)
                                .border(Color.gray, width: 1)
                            
                            ForEach(0..<game.nextShape.count, id: \.self) { row in
                                ForEach(0..<game.nextShape[0].count, id: \.self) { col in
                                    if game.nextShape[row][col] == 1 {
                                        game.nextColor
                                            .frame(width: blockSize - 1, height: blockSize - 1)
                                            .position(
                                                x: CGFloat(col) * blockSize + blockSize * 2,
                                                y: CGFloat(row) * blockSize + blockSize * 2
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 分数显示
                    Text("分数: \(game.score)")
                        .font(.headline)
                    
                    Spacer()
                    
                    // 控制按钮
                    if !game.isGameOver {
                        Button(isGameRunning ? "暂停" : "开始") {
                            toggleGame()
                        }
                        .padding()
                        .background(isGameRunning ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .frame(width: geometry.size.width * 0.3)
            }
            .padding()
        }
        .onAppear {
            setupGame()
        }
        .onDisappear {
            stopGame()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveGesture)) { notification in
            guard let gesture = notification.userInfo?["gesture"] as? String else { return }
            handleGesture(gesture)
        }
    }
    
    private func setupGame() {
        if bleService.isConnected {
            startGame()
        }
    }
    
    private func startGame() {
        isGameRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: gameSpeed, repeats: true) { _ in
            if !game.isGameOver {
                _ = game.moveDown()
            }
        }
    }
    
    private func stopGame() {
        isGameRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func toggleGame() {
        if isGameRunning {
            stopGame()
        } else {
            startGame()
        }
    }
    
    private func restartGame() {
        game.reset()
        startGame()
    }
    
    private func handleGesture(_ gesture: String) {
        guard isGameRunning && !game.isGameOver else { return }
        
        switch gesture {
        case let g where g.contains("左摆") || g.contains("左滑"):
            _ = game.moveLeft()
        case let g where g.contains("右摆") || g.contains("右滑"):
            _ = game.moveRight()
        case let g where g.contains("转腕"):
            game.rotate()
        case let g where g.contains("单击"):
            while game.moveDown() { }
        default:
            break
        }
    }
} 