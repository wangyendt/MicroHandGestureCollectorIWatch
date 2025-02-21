package com.wayne.android.tetris;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;
import android.util.DisplayMetrics;
import android.view.WindowManager;

public class TetrisView extends View {
    private final Paint paint;
    private TetrisGame game;
    private int blockSize;
    private static final int PADDING = 2;
    
    public TetrisView(Context context) {
        super(context);
        paint = new Paint();
        paint.setStyle(Paint.Style.FILL);
        
        // 计算合适的方块大小
        WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics metrics = new DisplayMetrics();
        wm.getDefaultDisplay().getMetrics(metrics);
        
        // 计算方块大小：使用屏幕的最大可用空间
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        
        // 计算基于宽度的块大小（使用98%的屏幕宽度）
        int blockSizeFromWidth = (int) ((screenWidth * 0.98) / (TetrisGame.COLS + 4));
        // 计算基于高度的块大小（使用95%的屏幕高度）
        int blockSizeFromHeight = (int) ((screenHeight * 0.95) / TetrisGame.ROWS);
        
        // 使用较大的值以确保游戏区域足够大
        blockSize = Math.max(blockSizeFromWidth, blockSizeFromHeight);
        
        // 确保块大小不小于最小值
        blockSize = Math.max(blockSize, 50);
        
        // 如果计算出的总宽度超过屏幕，则按比例缩小
        int totalWidth = (TetrisGame.COLS + 4) * blockSize;
        if (totalWidth > screenWidth) {
            blockSize = (int) ((screenWidth * 0.98) / (TetrisGame.COLS + 4));
        }
        
        // 如果计算出的总高度超过屏幕，则按比例缩小
        int totalHeight = TetrisGame.ROWS * blockSize;
        if (totalHeight > screenHeight * 0.95) {
            blockSize = (int) ((screenHeight * 0.95) / TetrisGame.ROWS);
        }
    }
    
    public void setGame(TetrisGame game) {
        this.game = game;
        invalidate();
    }
    
    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (game == null) return;
        
        // 计算游戏区域的中心位置
        int gameWidth = TetrisGame.COLS * blockSize;
        int totalWidth = getWidth();
        int startX = (totalWidth - gameWidth) / 2;
        
        // 绘制背景
        paint.setColor(Color.BLACK);
        canvas.drawRect(0, 0, getWidth(), getHeight(), paint);
        
        // 移动画布到游戏区域的开始位置
        canvas.save();
        canvas.translate(startX, 0);
        
        // 绘制网格
        paint.setColor(Color.DKGRAY);
        for (int i = 0; i <= TetrisGame.ROWS; i++) {
            canvas.drawLine(0, i * blockSize, gameWidth, i * blockSize, paint);
        }
        for (int i = 0; i <= TetrisGame.COLS; i++) {
            canvas.drawLine(i * blockSize, 0, i * blockSize, TetrisGame.ROWS * blockSize, paint);
        }
        
        // 绘制已固定的方块
        int[][] board = game.getBoard();
        for (int i = 0; i < TetrisGame.ROWS; i++) {
            for (int j = 0; j < TetrisGame.COLS; j++) {
                if (board[i][j] != 0) {
                    drawBlock(canvas, j, i, board[i][j]);
                }
            }
        }
        
        // 绘制当前方块
        int[][] currentShape = game.getCurrentShape();
        int currentRow = game.getCurrentRow();
        int currentCol = game.getCurrentCol();
        int currentColor = game.getCurrentColor();
        
        for (int i = 0; i < currentShape.length; i++) {
            for (int j = 0; j < currentShape[0].length; j++) {
                if (currentShape[i][j] == 1) {
                    drawBlock(canvas, currentCol + j, currentRow + i, currentColor);
                }
            }
        }
        
        // 恢复画布状态
        canvas.restore();
        
        // 在右侧绘制信息
        paint.setColor(Color.WHITE);
        paint.setTextSize(blockSize * 0.8f);
        
        // 绘制下一个方块预览
        canvas.drawText("下一个:", totalWidth - 3 * blockSize, blockSize, paint);
        
        int[][] nextShape = game.getNextShape();
        int nextColor = game.getNextColor();
        int previewX = totalWidth - 3 * blockSize;
        int previewY = (int) (blockSize * 1.5);
        
        for (int i = 0; i < nextShape.length; i++) {
            for (int j = 0; j < nextShape[0].length; j++) {
                if (nextShape[i][j] == 1) {
                    paint.setColor(nextColor);
                    canvas.drawRect(
                        previewX + j * blockSize * 0.8f,
                        previewY + i * blockSize * 0.8f,
                        previewX + (j + 1) * blockSize * 0.8f - PADDING,
                        previewY + (i + 1) * blockSize * 0.8f - PADDING,
                        paint
                    );
                }
            }
        }
        
        // 绘制分数
        paint.setColor(Color.WHITE);
        canvas.drawText("分数: " + game.getScore(), 
                       totalWidth - 3 * blockSize,
                       blockSize * 5, paint);
        
        // 如果游戏结束，显示游戏结束文字
        if (game.isGameOver()) {
            paint.setColor(Color.RED);
            paint.setTextSize(blockSize * 1.5f);
            canvas.drawText("游戏结束!", 
                          startX + gameWidth / 4,
                          TetrisGame.ROWS * blockSize / 2,
                          paint);
        }
    }
    
    private void drawBlock(Canvas canvas, int col, int row, int color) {
        paint.setColor(color);
        RectF rect = new RectF(
            col * blockSize + PADDING,
            row * blockSize + PADDING,
            (col + 1) * blockSize - PADDING,
            (row + 1) * blockSize - PADDING
        );
        canvas.drawRect(rect, paint);
    }
    
    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        // 计算理想的宽度和高度
        int width = (TetrisGame.COLS + 4) * blockSize; // 减少侧边预览区域的宽度
        int height = TetrisGame.ROWS * blockSize;
        
        // 获取父容器的宽度和高度
        int parentWidth = View.MeasureSpec.getSize(widthMeasureSpec);
        int parentHeight = View.MeasureSpec.getSize(heightMeasureSpec);
        
        // 如果需要，按比例缩小以适应父容器
        if (width > parentWidth || height > parentHeight) {
            float scaleW = (float) parentWidth / width;
            float scaleH = (float) parentHeight / height;
            float scale = Math.min(scaleW, scaleH);
            
            width = (int) (width * scale);
            height = (int) (height * scale);
            blockSize = (int) (blockSize * scale);
        }
        
        setMeasuredDimension(width, height);
    }
} 