import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
from collections import deque
import socket
import json
import threading
from datetime import datetime
import queue

# 创建固定长度的双端队列来存储最近的数据
WINDOW_SIZE = 300  # 3秒数据
PLOT_INTERVAL = 10  # 每次动画更新添加的数据点数
FPS = 60  # 动画刷新率

# 数据队列
acc_x = deque(maxlen=WINDOW_SIZE)
acc_y = deque(maxlen=WINDOW_SIZE)
acc_z = deque(maxlen=WINDOW_SIZE)
gyro_x = deque(maxlen=WINDOW_SIZE)
gyro_y = deque(maxlen=WINDOW_SIZE)
gyro_z = deque(maxlen=WINDOW_SIZE)
timestamps = deque(maxlen=WINDOW_SIZE)

# 缓冲队列，用于存储待绘制的数据
data_buffer = queue.Queue()

# 创建图形和子图
plt.style.use('dark_background')  # 使用深色主题
fig = plt.figure(figsize=(12, 8))
ax1 = plt.subplot(211)
ax2 = plt.subplot(212)

# 初始化线条
lines_acc = []
lines_gyro = []

# 在全局变量部分添加
first_timestamp = None

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
                    point_data = {
                        'timestamp': item.get("timestamp", 0),  # 保持原始纳秒时间戳
                        'acc_x': item.get("acc_x", 0),
                        'acc_y': item.get("acc_y", 0),
                        'acc_z': item.get("acc_z", 0),
                        'gyro_x': item.get("gyro_x", 0),
                        'gyro_y': item.get("gyro_y", 0),
                        'gyro_z': item.get("gyro_z", 0)
                    }
                    data_buffer.put(point_data)
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
    ax1.set_ylabel('Total Acceleration (m/s²)')
    ax1.grid(True, alpha=0.2)
    
    # 初始化陀螺仪图表
    ax2.set_title('Gyroscope Data')
    ax2.set_xlabel('Time (s)')
    ax2.set_ylabel('Angular Velocity (rad/s)')
    ax2.grid(True, alpha=0.2)
    
    # 创建线条
    colors = ['#FF6B6B', '#4ECDC4', '#45B7D1']  # 使用更现代的配色
    for ax, data_queues in [(ax1, [acc_x, acc_y, acc_z]), (ax2, [gyro_x, gyro_y, gyro_z])]:
        lines = []
        for i, data in enumerate(data_queues):
            line, = ax.plot([], [], label=f"{'XYZ'[i]}-axis", color=colors[i], linewidth=2)
            lines.append(line)
        ax.legend(loc='upper right')
        if ax == ax1:
            lines_acc.extend(lines)
        else:
            lines_gyro.extend(lines)
    
    # 设置x轴格式
    ax1.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f"{x:.3f}s"))
    ax2.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f"{x:.3f}s"))
    
    return lines_acc + lines_gyro

def update_plot_data():
    global first_timestamp
    # 从缓冲队列中获取新的数据点
    points_to_add = min(PLOT_INTERVAL, data_buffer.qsize())
    for _ in range(points_to_add):
        if data_buffer.empty():
            break
        
        point = data_buffer.get()
        current_timestamp = point['timestamp']
        
        # 设置第一个时间戳作为参考点
        if first_timestamp is None:
            first_timestamp = current_timestamp
        
        # 存储相对时间（秒）
        timestamps.append((current_timestamp - first_timestamp) / 1_000_000_000.0)
        acc_x.append(point['acc_x'])
        acc_y.append(point['acc_y'])
        acc_z.append(point['acc_z'])
        gyro_x.append(point['gyro_x'])
        gyro_y.append(point['gyro_y'])
        gyro_z.append(point['gyro_z'])

def animate(frame):
    update_plot_data()
    
    if not timestamps:
        return lines_acc + lines_gyro
    
    # 直接使用已经转换好的相对时间
    relative_times = list(timestamps)
    
    # 更新x轴范围
    current_time = relative_times[-1]
    window_size = 3.0  # 3秒窗口
    start_time = max(0, current_time - window_size)
    
    # 动态更新x轴，添加一点余量
    padding = window_size * 0.1
    ax1.set_xlim(start_time - padding, current_time + padding)
    ax2.set_xlim(start_time - padding, current_time + padding)
    
    # 更新x轴标签格式
    def format_time(x, p):
        return f"{x:.3f}s"
    
    ax1.xaxis.set_major_formatter(plt.FuncFormatter(format_time))
    ax2.xaxis.set_major_formatter(plt.FuncFormatter(format_time))
    
    # 获取当前窗口内的数据
    window_indices = [i for i, t in enumerate(relative_times) if t >= start_time]
    if window_indices:
        # 加速度计y轴范围
        window_acc_x = [acc_x[i] for i in window_indices]
        window_acc_y = [acc_y[i] for i in window_indices]
        window_acc_z = [acc_z[i] for i in window_indices]
        all_acc = window_acc_x + window_acc_y + window_acc_z
        if all_acc:
            acc_min, acc_max = min(all_acc), max(all_acc)
            acc_range = max(abs(acc_min), abs(acc_max))
            acc_padding = acc_range * 0.1
            acc_min = min(-9.81, acc_min - acc_padding)  # 至少显示重力加速度范围
            acc_max = max(9.81, acc_max + acc_padding)
            ax1.set_ylim(acc_min, acc_max)
        
        # 陀螺仪y轴范围
        window_gyro_x = [gyro_x[i] for i in window_indices]
        window_gyro_y = [gyro_y[i] for i in window_indices]
        window_gyro_z = [gyro_z[i] for i in window_indices]
        all_gyro = window_gyro_x + window_gyro_y + window_gyro_z
        if all_gyro:
            gyro_min, gyro_max = min(all_gyro), max(all_gyro)
            gyro_range = max(abs(gyro_min), abs(gyro_max))
            gyro_padding = gyro_range * 0.1
            gyro_min = min(-0.1, gyro_min - gyro_padding)  # 确保至少显示±0.1
            gyro_max = max(0.1, gyro_max + gyro_padding)
            ax2.set_ylim(gyro_min, gyro_max)
    
    # 更新数据
    for line, data in zip(lines_acc, [acc_x, acc_y, acc_z]):
        line.set_data(relative_times, list(data))
    
    for line, data in zip(lines_gyro, [gyro_x, gyro_y, gyro_z]):
        line.set_data(relative_times, list(data))
    
    # 更新标签显示当前值
    if acc_x:
        current_acc = (acc_x[-1], acc_y[-1], acc_z[-1])
        ax1.set_ylabel(f'Total Acceleration (m/s²)\nX: {current_acc[0]:.2f}\nY: {current_acc[1]:.2f}\nZ: {current_acc[2]:.2f}')
    
    if gyro_x:
        current_gyro = (gyro_x[-1], gyro_y[-1], gyro_z[-1])
        ax2.set_ylabel(f'Angular Velocity (rad/s)\nX: {current_gyro[0]:.2f}\nY: {current_gyro[1]:.2f}\nZ: {current_gyro[2]:.2f}')
    
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
        interval=1000/FPS,  # 60 FPS
        blit=False
    )
    
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()