package com.wayne.android.tetris;

import android.graphics.Color;
import java.util.Random;

public class TetrisGame {
    public static final int ROWS = 20;
    public static final int COLS = 10;
    private static final int BLOCK_SIZE = 30;
    
    // 方块形状定义
    private static final int[][][] SHAPES = {
        // I
        {{1,1,1,1}},
        // L
        {{1,0}, {1,0}, {1,1}},
        // J
        {{0,1}, {0,1}, {1,1}},
        // O
        {{1,1}, {1,1}},
        // S
        {{0,1,1}, {1,1,0}},
        // Z
        {{1,1,0}, {0,1,1}},
        // T
        {{1,1,1}, {0,1,0}}
    };
    
    // 方块颜色
    private static final int[] COLORS = {
        Color.CYAN,    // I
        Color.BLUE,    // L
        Color.YELLOW,  // J
        Color.GREEN,   // O
        Color.RED,     // S
        Color.MAGENTA, // Z
        Color.rgb(255, 165, 0)  // T - Orange
    };
    
    private int[][] board;
    private int[][] currentShape;
    private int currentColor;
    private int nextShapeIndex;
    private int nextColor;
    private int currentRow;
    private int currentCol;
    private int score;
    private boolean isGameOver;
    private Random random;
    
    public TetrisGame() {
        board = new int[ROWS][COLS];
        random = new Random();
        score = 0;
        isGameOver = false;
        prepareNextShape();
        spawnNewShape();
    }
    
    private void prepareNextShape() {
        nextShapeIndex = random.nextInt(SHAPES.length);
        nextColor = COLORS[nextShapeIndex];
    }
    
    public void spawnNewShape() {
        currentShape = SHAPES[nextShapeIndex];
        currentColor = nextColor;
        currentRow = 0;
        currentCol = COLS/2 - currentShape[0].length/2;
        
        if (!canMove(currentRow, currentCol)) {
            isGameOver = true;
        }
        
        prepareNextShape();
    }
    
    public boolean moveLeft() {
        if (canMove(currentRow, currentCol - 1)) {
            currentCol--;
            return true;
        }
        return false;
    }
    
    public boolean moveRight() {
        if (canMove(currentRow, currentCol + 1)) {
            currentCol++;
            return true;
        }
        return false;
    }
    
    public boolean moveDown() {
        if (canMove(currentRow + 1, currentCol)) {
            currentRow++;
            return true;
        }
        
        // 如果不能下移，则固定当前方块
        freezeShape();
        clearLines();
        spawnNewShape();
        return false;
    }
    
    public void rotate() {
        int[][] rotated = new int[currentShape[0].length][currentShape.length];
        for (int i = 0; i < currentShape.length; i++) {
            for (int j = 0; j < currentShape[0].length; j++) {
                rotated[j][currentShape.length-1-i] = currentShape[i][j];
            }
        }
        
        if (canPlaceShape(rotated, currentRow, currentCol)) {
            currentShape = rotated;
        }
    }
    
    private boolean canMove(int newRow, int newCol) {
        return canPlaceShape(currentShape, newRow, newCol);
    }
    
    private boolean canPlaceShape(int[][] shape, int row, int col) {
        for (int i = 0; i < shape.length; i++) {
            for (int j = 0; j < shape[0].length; j++) {
                if (shape[i][j] == 0) continue;
                
                int boardRow = row + i;
                int boardCol = col + j;
                
                if (boardRow < 0 || boardRow >= ROWS || 
                    boardCol < 0 || boardCol >= COLS ||
                    board[boardRow][boardCol] != 0) {
                    return false;
                }
            }
        }
        return true;
    }
    
    private void freezeShape() {
        for (int i = 0; i < currentShape.length; i++) {
            for (int j = 0; j < currentShape[0].length; j++) {
                if (currentShape[i][j] == 1) {
                    board[currentRow + i][currentCol + j] = currentColor;
                }
            }
        }
    }
    
    private void clearLines() {
        int linesCleared = 0;
        
        for (int i = ROWS - 1; i >= 0; i--) {
            boolean isLineFull = true;
            for (int j = 0; j < COLS; j++) {
                if (board[i][j] == 0) {
                    isLineFull = false;
                    break;
                }
            }
            
            if (isLineFull) {
                linesCleared++;
                // 移动所有行下来
                for (int k = i; k > 0; k--) {
                    System.arraycopy(board[k-1], 0, board[k], 0, COLS);
                }
                // 清空顶行
                for (int j = 0; j < COLS; j++) {
                    board[0][j] = 0;
                }
                i++; // 重新检查当前行，因为上面的行已经下移
            }
        }
        
        // 更新分数
        if (linesCleared > 0) {
            score += Math.pow(2, linesCleared - 1) * 100; // 1行100分，2行200分，3行400分，4行800分
        }
    }
    
    // Getters
    public int[][] getBoard() {
        return board;
    }
    
    public int[][] getCurrentShape() {
        return currentShape;
    }
    
    public int getCurrentColor() {
        return currentColor;
    }
    
    public int getCurrentRow() {
        return currentRow;
    }
    
    public int getCurrentCol() {
        return currentCol;
    }
    
    public int getScore() {
        return score;
    }
    
    public boolean isGameOver() {
        return isGameOver;
    }
    
    public int[][] getNextShape() {
        return SHAPES[nextShapeIndex];
    }
    
    public int getNextColor() {
        return nextColor;
    }
} 