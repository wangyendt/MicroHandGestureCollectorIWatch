package com.wayne.android;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.EdgeToEdge;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;

import com.wayne.android.tetris.TetrisGame;
import com.wayne.android.tetris.TetrisView;

public class MainActivity extends AppCompatActivity {

    private BluetoothAdapter bluetoothAdapter;
    private BlePeripheralService blePeripheralService;
    private static final int PERMISSION_REQUEST_CODE = 1;
    private Handler handler = new Handler();
    private int currentValue = 0;
    
    // 添加游戏相关变量
    private TetrisGame tetrisGame;
    private TetrisView tetrisView;
    private Handler gameHandler = new Handler();
    private static final long GAME_TICK = 1000; // 1秒一次下落
    private boolean isGameRunning = false;

    private final ActivityResultLauncher<Intent> enableBtLauncher = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(),
            result -> {
                if (result.getResultCode() == RESULT_OK) {
                    startBlePeripheral();
                } else {
                    Toast.makeText(this, "需要开启蓝牙才能使用此功能", Toast.LENGTH_SHORT).show();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        setContentView(R.layout.activity_main);

        // 初始化游戏
        initGame();

        blePeripheralService = new BlePeripheralService(this);
        blePeripheralService.setCallback(new BlePeripheralService.BleCallback() {
            @Override
            public void onDeviceConnected(String deviceAddress) {
                updateStatusText("已连接到设备: " + deviceAddress);
                // 连接成功后启动游戏
                startGame();
            }

            @Override
            public void onDeviceDisconnected(String deviceAddress) {
                updateStatusText("设备已断开连接");
                // 断开连接时暂停游戏
                pauseGame();
            }

            @Override
            public void onCounterUpdated(int value) {
                runOnUiThread(() -> {
                    TextView counterText = findViewById(R.id.counterText);
                    counterText.setText("当前计数: " + value);
                });
            }

            @Override
            public void onMessageReceived(String message) {
                handleGesture(message);
            }
        });

        // 启动蓝牙服务
        if (checkPermissions()) {
            blePeripheralService.startAdvertising();
            updateStatusText("正在等待设备连接...");
        }
    }

    private void initGame() {
        tetrisGame = new TetrisGame();
        tetrisView = new TetrisView(this);
        tetrisView.setGame(tetrisGame);
        
        FrameLayout gameContainer = findViewById(R.id.gameContainer);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        );
        gameContainer.addView(tetrisView, params);
    }

    private void startGame() {
        if (!isGameRunning) {
            isGameRunning = true;
            tetrisGame = new TetrisGame();
            tetrisView.setGame(tetrisGame);
            gameHandler.post(gameLoop);
        }
    }

    private void pauseGame() {
        isGameRunning = false;
        gameHandler.removeCallbacks(gameLoop);
    }

    private final Runnable gameLoop = new Runnable() {
        @Override
        public void run() {
            if (isGameRunning && !tetrisGame.isGameOver()) {
                tetrisGame.moveDown();
                tetrisView.invalidate();
                gameHandler.postDelayed(this, GAME_TICK);
            }
        }
    };

    private void handleGesture(String gesture) {
        if (!isGameRunning || tetrisGame == null || tetrisGame.isGameOver()) {
            Log.d("Tetris", "游戏未运行或已结束，忽略手势: " + gesture);
            return;
        }

        runOnUiThread(() -> {
            TextView gestureText = findViewById(R.id.gestureText);
            gestureText.setText("收到手势: " + gesture);
            
            boolean needRefresh = false;
            Log.d("Tetris", "处理手势: " + gesture);
            
            // 处理不同的手势名称变体
            if (gesture.contains("左摆") || gesture.contains("左滑")) {
                Log.d("Tetris", "执行左移");
                needRefresh = tetrisGame.moveLeft();
            } else if (gesture.contains("右摆") || gesture.contains("右滑")) {
                Log.d("Tetris", "执行右移");
                needRefresh = tetrisGame.moveRight();
            } else if (gesture.contains("转腕")) {
                Log.d("Tetris", "执行旋转");
                tetrisGame.rotate();
                needRefresh = true;
            } else if (gesture.contains("单击")) {
                Log.d("Tetris", "执行快速下落");
                // 快速下落
                while (tetrisGame.moveDown()) {
                    needRefresh = true;
                }
            }
            
            if (needRefresh) {
                Log.d("Tetris", "刷新视图");
                tetrisView.invalidate();
            } else {
                Log.d("Tetris", "操作未产生变化，不刷新");
            }
        });
    }

    private void checkPermissionsAndStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            String[] permissions = {
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.ACCESS_FINE_LOCATION
            };
            requestPermissions(permissions);
        } else {
            String[] permissions = {
                    Manifest.permission.ACCESS_FINE_LOCATION
            };
            requestPermissions(permissions);
        }
    }

    private void requestPermissions(String[] permissions) {
        boolean allGranted = true;
        for (String permission : permissions) {
            if (ActivityCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                allGranted = false;
                break;
            }
        }

        if (allGranted) {
            enableBluetooth();
        } else {
            ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST_CODE) {
            boolean allGranted = true;
            for (int result : grantResults) {
                if (result != PackageManager.PERMISSION_GRANTED) {
                    allGranted = false;
                    break;
                }
            }

            if (allGranted) {
                enableBluetooth();
            } else {
                Toast.makeText(this, "需要相关权限才能使用此功能", Toast.LENGTH_SHORT).show();
            }
        }
    }

    private void enableBluetooth() {
        if (!bluetoothAdapter.isEnabled()) {
            Intent enableBtIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
            enableBtLauncher.launch(enableBtIntent);
        } else {
            startBlePeripheral();
        }
    }

    private void startBlePeripheral() {
        blePeripheralService.startAdvertising();
        updateStatusText("BLE外围设备已启动");

        // 启动定时器，每秒更新一次计数
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                currentValue = (currentValue + 1) % 1000;
                blePeripheralService.updateCounter(currentValue);
                handler.postDelayed(this, 1000); // 1秒后再次执行
            }
        }, 1000);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        pauseGame();
        gameHandler.removeCallbacksAndMessages(null);
        handler.removeCallbacksAndMessages(null);
        if (blePeripheralService != null) {
            blePeripheralService.stop();
        }
    }

    private void updateStatusText(String status) {
        runOnUiThread(() -> {
            TextView statusText = findViewById(R.id.statusText);
            statusText.setText(status);
        });
    }

    private boolean checkPermissions() {
        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        bluetoothAdapter = bluetoothManager.getAdapter();

        if (bluetoothAdapter == null) {
            Toast.makeText(this, "此设备不支持蓝牙", Toast.LENGTH_SHORT).show();
            return false;
        }

        checkPermissionsAndStart();
        return true;
    }
}