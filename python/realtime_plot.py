import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
from collections import deque
import socket
import json
import threading
from datetime import datetime

# 创建固定长度的双端队列来存储最近的数据
WINDOW_SIZE = 300  # 假设100Hz采样率，3秒数据
acc_x = deque(maxlen=WINDOW_SIZE)
acc_y = deque(maxlen=WINDOW_SIZE)
acc_z = deque(maxlen=WINDOW_SIZE)
gyro_x = deque(maxlen=WINDOW_SIZE)
gyro_y = deque(maxlen=WINDOW_SIZE)
gyro_z = deque(maxlen=WINDOW_SIZE)
timestamps = deque(maxlen=WINDOW_SIZE)

# 创建图形和子图
fig = plt.figure(figsize=(12, 8))
ax1 = plt.subplot(211)  # 加速度计
ax2 = plt.subplot(212)  # 陀螺仪

# 初始化线条
lines_acc = []
lines_gyro = []

def setup_socket():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(('0.0.0.0', 12345))
    server_socket.listen(1)
    print("等待连接...")
    return server_socket

def process_data(data_str):
    try:
        data = json.loads(data_str)
        if data.get("type") == "batch_data":
            batch_data = data.get("data", [])
            if batch_data and isinstance(batch_data, list):
                for item in batch_data:
                    timestamp_ns = item.get("timestamp", 0)
                    timestamp_s = timestamp_ns / 1_000_000_000.0  # 转换为秒
                    
                    timestamps.append(timestamp_s)
                    acc_x.append(item.get("acc_x", 0))
                    acc_y.append(item.get("acc_y", 0))
                    acc_z.append(item.get("acc_z", 0))
                    gyro_x.append(item.get("gyro_x", 0))
                    gyro_y.append(item.get("gyro_y", 0))
                    gyro_z.append(item.get("gyro_z", 0))
                    
    except json.JSONDecodeError as e:
        print("JSON parsing error:", e)

def data_receiver(server_socket):
    while True:
        client_socket, address = server_socket.accept()
        print(f"接受来自 {address} 的连接")
        buffer = ""
        
        try:
            while True:
                data = client_socket.recv(1024).decode('utf-8')
                if not data:
                    break
                
                buffer += data
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    process_data(line)
                    
        except Exception as e:
            print(f"接收数据错误: {e}")
        finally:
            client_socket.close()

def init():
    # 初始化加速度计图表
    ax1.set_title('Accelerometer Data')
    ax1.set_ylabel('Acceleration (m/s²)')
    ax1.grid(True)
    
    # 初始化陀螺仪图表
    ax2.set_title('Gyroscope Data')
    ax2.set_xlabel('Time (s)')
    ax2.set_ylabel('Angular Velocity (rad/s)')
    ax2.grid(True)
    
    # 创建线条
    for ax, data_queues in [(ax1, [acc_x, acc_y, acc_z]), (ax2, [gyro_x, gyro_y, gyro_z])]:
        lines = []
        for i, data in enumerate(data_queues):
            line, = ax.plot([], [], label=f"{'XYZ'[i]}-axis")
            lines.append(line)
        ax.legend()
        if ax == ax1:
            lines_acc.extend(lines)
        else:
            lines_gyro.extend(lines)
    
    return lines_acc + lines_gyro

def animate(frame):
    if not timestamps:
        return lines_acc + lines_gyro
    
    # 获取时间范围
    current_time = timestamps[-1]
    start_time = current_time - 3.0  # 显示最近3秒的数据
    
    # 更新x轴范围
    ax1.set_xlim(start_time, current_time)
    ax2.set_xlim(start_time, current_time)
    
    # 更新y轴范围
    if acc_x:
        all_acc = list(acc_x) + list(acc_y) + list(acc_z)
        acc_min, acc_max = min(all_acc), max(all_acc)
        acc_range = max(abs(acc_min), abs(acc_max))
        ax1.set_ylim(-acc_range * 1.1, acc_range * 1.1)
    
    if gyro_x:
        all_gyro = list(gyro_x) + list(gyro_y) + list(gyro_z)
        gyro_min, gyro_max = min(all_gyro), max(all_gyro)
        gyro_range = max(abs(gyro_min), abs(gyro_max))
        ax2.set_ylim(-gyro_range * 1.1, gyro_range * 1.1)
    
    # 更新数据
    times = list(timestamps)
    for line, data in zip(lines_acc, [acc_x, acc_y, acc_z]):
        line.set_data(times, list(data))
    
    for line, data in zip(lines_gyro, [gyro_x, gyro_y, gyro_z]):
        line.set_data(times, list(data))
    
    return lines_acc + lines_gyro

def main():
    server_socket = setup_socket()
    
    # 启动数据接收线程
    receiver_thread = threading.Thread(target=data_receiver, args=(server_socket,))
    receiver_thread.daemon = True
    receiver_thread.start()
    
    # 设置动画
    ani = animation.FuncAnimation(
        fig, animate, init_func=init,
        interval=20,  # 50 FPS
        blit=True
    )
    
    plt.show()

if __name__ == "__main__":
    main() 