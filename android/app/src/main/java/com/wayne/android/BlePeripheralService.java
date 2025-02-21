package com.wayne.android;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.content.Context;
import android.os.ParcelUuid;
import android.util.Log;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class BlePeripheralService {
    private static final String TAG = "BlePeripheralService";

    // 自定义UUID
    public static final UUID SERVICE_UUID = UUID.fromString("0000180D-0000-1000-8000-00805F9B34FB");
    public static final UUID NOTIFY_CHARACTERISTIC_UUID = UUID.fromString("00002A37-0000-1000-8000-00805F9B34FB");
    public static final UUID WRITE_CHARACTERISTIC_UUID = UUID.fromString("00002A38-0000-1000-8000-00805F9B34FB");

    private Context context;
    private BluetoothManager bluetoothManager;
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothGattServer gattServer;
    private List<BluetoothDevice> connectedDevices = new ArrayList<>();
    private BleCallback callback;

    private int currentValue = 0;

    public interface BleCallback {
        void onDeviceConnected(String deviceAddress);
        void onDeviceDisconnected(String deviceAddress);
        void onCounterUpdated(int value);
        void onMessageReceived(String message);
    }

    public BlePeripheralService(Context context) {
        this.context = context;
        bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        bluetoothAdapter = bluetoothManager.getAdapter();
    }

    public void setCallback(BleCallback callback) {
        this.callback = callback;
    }

    public void startAdvertising() {
        advertiser = bluetoothAdapter.getBluetoothLeAdvertiser();
        if (advertiser == null) {
            Log.e(TAG, "设备不支持BLE广播");
            return;
        }

        AdvertiseSettings settings = new AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build();

        AdvertiseData data = new AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(new ParcelUuid(SERVICE_UUID))
                .build();

        advertiser.startAdvertising(settings, data, advertiseCallback);
        startGattServer();
    }

    private void startGattServer() {
        gattServer = bluetoothManager.openGattServer(context, gattServerCallback);
        BluetoothGattService service = new BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY);
        
        // 通知特性 - 用于发送计数器数据
        BluetoothGattCharacteristic notifyCharacteristic = new BluetoothGattCharacteristic(
                NOTIFY_CHARACTERISTIC_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ | BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ
        );
        
        // 写入特性 - 用于接收手势数据
        BluetoothGattCharacteristic writeCharacteristic = new BluetoothGattCharacteristic(
                WRITE_CHARACTERISTIC_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE | BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
        );
        
        service.addCharacteristic(notifyCharacteristic);
        service.addCharacteristic(writeCharacteristic);
        gattServer.addService(service);
    }

    public void updateCounter(int value) {
        currentValue = value;
        notifyValueChanged();
        if (callback != null) {
            callback.onCounterUpdated(currentValue);
        }
    }

    private void notifyValueChanged() {
        if (connectedDevices.isEmpty()) return;

        BluetoothGattCharacteristic characteristic = gattServer
                .getService(SERVICE_UUID)
                .getCharacteristic(NOTIFY_CHARACTERISTIC_UUID);

        byte[] value = String.valueOf(currentValue).getBytes();
        characteristic.setValue(value);

        for (BluetoothDevice device : connectedDevices) {
            gattServer.notifyCharacteristicChanged(device, characteristic, false);
        }
    }

    public void stop() {
        if (advertiser != null) {
            advertiser.stopAdvertising(advertiseCallback);
        }
        if (gattServer != null) {
            gattServer.close();
        }
        connectedDevices.clear();
    }

    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override
        public void onStartSuccess(AdvertiseSettings settingsInEffect) {
            Log.i(TAG, "BLE广播已启动");
        }

        @Override
        public void onStartFailure(int errorCode) {
            Log.e(TAG, "BLE广播启动失败: " + errorCode);
        }
    };

    private final BluetoothGattServerCallback gattServerCallback = new BluetoothGattServerCallback() {
        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                connectedDevices.add(device);
                Log.i(TAG, "设备已连接: " + device.getAddress());
                if (callback != null) {
                    callback.onDeviceConnected(device.getAddress());
                }
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                connectedDevices.remove(device);
                Log.i(TAG, "设备已断开: " + device.getAddress());
                if (callback != null) {
                    callback.onDeviceDisconnected(device.getAddress());
                }
            }
        }

        @Override
        public void onCharacteristicWriteRequest(BluetoothDevice device, int requestId, BluetoothGattCharacteristic characteristic,
                                               boolean preparedWrite, boolean responseNeeded, int offset, byte[] value) {
            if (characteristic.getUuid().equals(WRITE_CHARACTERISTIC_UUID)) {
                // 处理接收到的手势数据
                String receivedData = new String(value);
                Log.i(TAG, "收到手势数据: " + receivedData);
                
                if (callback != null) {
                    callback.onMessageReceived(receivedData);
                }
                
                // 如果需要响应
                if (responseNeeded) {
                    gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null);
                }
            }
        }
    };
} 