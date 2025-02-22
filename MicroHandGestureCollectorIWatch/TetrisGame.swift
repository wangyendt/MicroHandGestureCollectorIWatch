import SwiftUI

class TetrisGame: ObservableObject {
    static let ROWS = 20
    static let COLS = 10
    
    // 方块形状定义
    private static let SHAPES: [[[Int]]] = [
        // I
        [[1,1,1,1]],
        // L
        [[1,0], [1,0], [1,1]],
        // J
        [[0,1], [0,1], [1,1]],
        // O
        [[1,1], [1,1]],
        // S
        [[0,1,1], [1,1,0]],
        // Z
        [[1,1,0], [0,1,1]],
        // T
        [[1,1,1], [0,1,0]]
    ]
    
    // 方块颜色
    private static let COLORS: [Color] = [
        .cyan,    // I
        .blue,    // L
        .yellow,  // J
        .green,   // O
        .red,     // S
        .purple,  // Z
        .orange   // T
    ]
    
    @Published private(set) var board: [[Color?]]
    @Published private(set) var currentShape: [[Int]]
    @Published private(set) var currentColor: Color
    @Published private(set) var nextShapeIndex: Int
    @Published private(set) var nextColor: Color
    @Published private(set) var currentRow: Int
    @Published private(set) var currentCol: Int
    @Published private(set) var score: Int
    @Published private(set) var isGameOver: Bool
    
    init() {
        board = Array(repeating: Array(repeating: nil, count: TetrisGame.COLS), count: TetrisGame.ROWS)
        currentShape = [[]]
        currentColor = .clear
        nextShapeIndex = 0
        nextColor = .clear
        currentRow = 0
        currentCol = 0
        score = 0
        isGameOver = false
        
        prepareNextShape()
        spawnNewShape()
    }
    
    private func prepareNextShape() {
        nextShapeIndex = Int.random(in: 0..<TetrisGame.SHAPES.count)
        nextColor = TetrisGame.COLORS[nextShapeIndex]
    }
    
    func spawnNewShape() {
        currentShape = TetrisGame.SHAPES[nextShapeIndex]
        currentColor = nextColor
        currentRow = 0
        currentCol = TetrisGame.COLS/2 - currentShape[0].count/2
        
        if !canMove(to: currentRow, col: currentCol) {
            isGameOver = true
        }
        
        prepareNextShape()
        objectWillChange.send()
    }
    
    func moveLeft() -> Bool {
        if canMove(to: currentRow, col: currentCol - 1) {
            currentCol -= 1
            objectWillChange.send()
            return true
        }
        return false
    }
    
    func moveRight() -> Bool {
        if canMove(to: currentRow, col: currentCol + 1) {
            currentCol += 1
            objectWillChange.send()
            return true
        }
        return false
    }
    
    func moveDown() -> Bool {
        if canMove(to: currentRow + 1, col: currentCol) {
            currentRow += 1
            objectWillChange.send()
            return true
        }
        
        freezeShape()
        clearLines()
        spawnNewShape()
        return false
    }
    
    func rotate() {
        let rows = currentShape[0].count
        let cols = currentShape.count
        var rotated = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        
        for i in 0..<cols {
            for j in 0..<rows {
                rotated[j][cols-1-i] = currentShape[i][j]
            }
        }
        
        if canPlaceShape(rotated, at: currentRow, col: currentCol) {
            currentShape = rotated
            objectWillChange.send()
        }
    }
    
    private func canMove(to row: Int, col: Int) -> Bool {
        return canPlaceShape(currentShape, at: row, col: col)
    }
    
    private func canPlaceShape(_ shape: [[Int]], at row: Int, col: Int) -> Bool {
        for i in 0..<shape.count {
            for j in 0..<shape[0].count {
                if shape[i][j] == 0 { continue }
                
                let boardRow = row + i
                let boardCol = col + j
                
                if boardRow < 0 || boardRow >= TetrisGame.ROWS ||
                    boardCol < 0 || boardCol >= TetrisGame.COLS ||
                    board[boardRow][boardCol] != nil {
                    return false
                }
            }
        }
        return true
    }
    
    private func freezeShape() {
        for i in 0..<currentShape.count {
            for j in 0..<currentShape[0].count {
                if currentShape[i][j] == 1 {
                    board[currentRow + i][currentCol + j] = currentColor
                }
            }
        }
        objectWillChange.send()
    }
    
    private func clearLines() {
        var linesCleared = 0
        var row = TetrisGame.ROWS - 1
        
        while row >= 0 {
            if board[row].allSatisfy({ $0 != nil }) {
                linesCleared += 1
                // 移动所有行下来
                for i in (1...row).reversed() {
                    board[i] = board[i-1]
                }
                // 清空顶行
                board[0] = Array(repeating: nil, count: TetrisGame.COLS)
                row += 1 // 重新检查当前行
            }
            row -= 1
        }
        
        // 更新分数
        if linesCleared > 0 {
            score += Int(pow(2.0, Double(linesCleared - 1))) * 100
            objectWillChange.send()
        }
    }
    
    // 获取下一个方块形状
    var nextShape: [[Int]] {
        return TetrisGame.SHAPES[nextShapeIndex]
    }
    
    func reset() {
        board = Array(repeating: Array(repeating: nil, count: TetrisGame.COLS), count: TetrisGame.ROWS)
        score = 0
        isGameOver = false
        prepareNextShape()
        spawnNewShape()
        objectWillChange.send()
    }
} 