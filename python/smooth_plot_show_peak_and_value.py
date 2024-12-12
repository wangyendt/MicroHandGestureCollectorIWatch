import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
from collections import deque
import socket
import json
import threading
from datetime import datetime
import queue
from scipy import interpolate

# 在文件开头添加OneEuroFilter类定义
class OneEuroFilter:
    """
    常用于pose tracking等场景
    低速时去抖，高速时紧跟
    https://gery.casiez.net/1euro/
    """

    def __init__(self, te, mincutoff=1.0, beta=0.007, dcutoff=1.0):
        self._val = None
        self._dx = 0
        self._te = te
        self._mincutoff = mincutoff
        self._beta = beta
        self._dcutoff = dcutoff
        self._alpha_value = self._compute_alpha(self._mincutoff)
        self._dalpha = self._compute_alpha(self._dcutoff)

    def _compute_alpha(self, cutoff):
        tau = 1.0 / (2 * np.pi * cutoff)
        return 1.0 / (1.0 + tau / self._te)

    def apply(self, val: float, te: float) -> float:
        result = val
        if self._val is not None:
            edx = (val - self._val) / te
            self._dx = self._dx + (self._dalpha * (edx - self._dx))
            cutoff = self._mincutoff + self._beta * abs(self._dx)
            self._alpha_value = self._compute_alpha(cutoff)
            result = self._val + self._alpha_value * (val - self._val)
        self._val = result
        return result

# 修改常量定义
WINDOW_SIZE = 1000  # 10秒数据，100Hz
PLOT_INTERVAL = 10
FPS = 60
PEAK_DELTA = 0.3  # peak detection的阈值
SAMPLE_TIME = 0.01  # 采样时间(100Hz)

# 数据队列
timestamps = deque(maxlen=WINDOW_SIZE)
acc_norm = deque(maxlen=WINDOW_SIZE)
gyro_norm = deque(maxlen=WINDOW_SIZE)
acc_diff = deque(maxlen=WINDOW_SIZE)  # 存储导数
gyro_diff = deque(maxlen=WINDOW_SIZE)  # 存储导数
filtered_acc_diff = deque(maxlen=WINDOW_SIZE)  # 存储滤波后的导数
filtered_gyro_diff = deque(maxlen=WINDOW_SIZE)  # 存储滤波后的导数

# Peak detection状态变量
acc_lookformax = True
gyro_lookformax = True
acc_mn, acc_mx = np.Inf, -np.Inf
gyro_mn, gyro_mx = np.Inf, -np.Inf
acc_peaks = deque(maxlen=100)  # 存储peak的时间和值
acc_valleys = deque(maxlen=100)
gyro_peaks = deque(maxlen=100)
gyro_valleys = deque(maxlen=100)

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

# 在全局变量部分添加滤波器实例
acc_filter = OneEuroFilter(te=SAMPLE_TIME, mincutoff=10.0, beta=0.001, dcutoff=1.0)
gyro_filter = OneEuroFilter(te=SAMPLE_TIME, mincutoff=10.0, beta=0.001, dcutoff=1.0)

# 修改全局变量部分，添加存储最大最小值对应时间戳的变量
acc_mx_time, acc_mn_time = 0, 0
gyro_mx_time, gyro_mn_time = 0, 0

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
    ax1.set_title('Accelerometer Norm')
    ax1.set_ylabel('Total Acceleration (m/s²)')
    ax1.grid(True, alpha=0.2)
    
    # 初始化陀螺仪图表
    ax2.set_title('Gyroscope Norm')
    ax2.set_xlabel('Time (s)')
    ax2.set_ylabel('Angular Velocity (rad/s)')
    ax2.grid(True, alpha=0.2)
    
    # 创建线条 - 只需要norm的线条
    colors = ['#FF9F1C', '#4ECDC4']  # 原始norm用橙色，滤波后的norm用青色
    for ax in [ax1, ax2]:
        lines = []
        # 原始norm线条
        line, = ax.plot([], [], label='Original', color=colors[0], linewidth=1, alpha=0.5)
        lines.append(line)
        # 滤波后的norm线条
        line, = ax.plot([], [], label='Filtered', color=colors[1], linewidth=2)
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

def interpolate_data(times, values, target_freq=100):
    """对数据进行插值，确保严格100Hz采样"""
    if len(times) < 2:
        return [], []
    
    # 创建均匀时间序列
    t_start = times[0]
    t_end = times[-1]
    t_new = np.arange(t_start, t_end, 1/target_freq)
    
    # 进行插值
    f = interpolate.interp1d(times, values, kind='linear', fill_value='extrapolate')
    v_new = f(t_new)
    
    return t_new, v_new

def online_peak_detection(value, timestamp, lookformax, mn, mx, mn_time, mx_time, delta):
    """在线peak detection
    Args:
        value: 当前值
        timestamp: 当前时间戳
        lookformax: 是否在寻找最大值
        mn: 当前最小值
        mx: 当前最大值
        mn_time: 最小值对应的时间戳
        mx_time: 最大值对应的时间戳
        delta: 检测阈值
    """
    peak = None
    peak_time = None
    valley = None
    valley_time = None
    is_peak = False
    is_valley = False
    
    if lookformax:
        if value > mx:
            mx = value
            mx_time = timestamp
        elif (mx - value) > delta:
            peak = mx
            peak_time = mx_time
            mn = value
            mn_time = timestamp
            lookformax = False
            is_peak = True
        elif value < mx and (mx - value) > delta * 0.5:
            peak = mx
            peak_time = mx_time
            mn = value
            mn_time = timestamp
            lookformax = False
            is_peak = True
    else:
        if value < mn:
            mn = value
            mn_time = timestamp
        elif (value - mn) > delta:
            valley = mn
            valley_time = mn_time
            mx = value
            mx_time = timestamp
            lookformax = True
            is_valley = True
        elif value > mn and (value - mn) > delta * 0.5:
            valley = mn
            valley_time = mn_time
            mx = value
            mx_time = timestamp
            lookformax = True
            is_valley = True
            
    return peak, peak_time, valley, valley_time, lookformax, mn, mx, mn_time, mx_time, is_peak, is_valley

def update_plot_data():
    global first_timestamp, acc_lookformax, gyro_lookformax
    global acc_mn, acc_mx, gyro_mn, gyro_mx
    global acc_mx_time, acc_mn_time, gyro_mx_time, gyro_mn_time
    
    points_to_add = min(PLOT_INTERVAL, data_buffer.qsize())
    last_timestamp = None
    
    for _ in range(points_to_add):
        if data_buffer.empty():
            break
            
        point = data_buffer.get()
        current_timestamp = point['timestamp']
        
        if first_timestamp is None:
            first_timestamp = current_timestamp
            
        rel_time = (current_timestamp - first_timestamp) / 1_000_000_000.0
        
        # 计算实际的时间间隔
        te = SAMPLE_TIME if last_timestamp is None else (current_timestamp - last_timestamp) / 1_000_000_000.0
        last_timestamp = current_timestamp
        
        # 计算norm值
        acc_norm_val = np.sqrt(point['acc_x']**2 + point['acc_y']**2 + point['acc_z']**2)
        gyro_norm_val = np.sqrt(point['gyro_x']**2 + point['gyro_y']**2 + point['gyro_z']**2)
        
        # 更新数据队列
        timestamps.append(rel_time)
        acc_norm.append(acc_norm_val)
        gyro_norm.append(gyro_norm_val)
        
        # 计算并滤波导数
        if len(acc_norm) > 1:
            curr_acc_diff = abs(acc_norm[-1] - acc_norm[-2])
            curr_gyro_diff = abs(gyro_norm[-1] - gyro_norm[-2])
            
            curr_filtered_acc_diff = acc_filter.apply(curr_acc_diff, te)
            curr_filtered_gyro_diff = gyro_filter.apply(curr_gyro_diff, te)
            
            # Peak detection使用滤波后的导数
            (acc_peak, acc_peak_time, acc_valley, acc_valley_time, 
             acc_lookformax, acc_mn, acc_mx, acc_mn_time, acc_mx_time,
             is_acc_peak, is_acc_valley) = online_peak_detection(
                curr_filtered_acc_diff, rel_time, acc_lookformax, 
                acc_mn, acc_mx, acc_mn_time, acc_mx_time, PEAK_DELTA)
            
            (gyro_peak, gyro_peak_time, gyro_valley, gyro_valley_time,
             gyro_lookformax, gyro_mn, gyro_mx, gyro_mn_time, gyro_mx_time,
             is_gyro_peak, is_gyro_valley) = online_peak_detection(
                curr_filtered_gyro_diff, rel_time, gyro_lookformax,
                gyro_mn, gyro_mx, gyro_mn_time, gyro_mx_time, PEAK_DELTA)
            
            # 存储peaks和valleys（使用实际的峰值时间）
            if is_acc_peak:
                acc_peaks.append((acc_peak_time, acc_peak))
            if is_acc_valley:
                acc_valleys.append((acc_valley_time, acc_valley))
            if is_gyro_peak:
                gyro_peaks.append((gyro_peak_time, gyro_peak))
            if is_gyro_valley:
                gyro_valleys.append((gyro_valley_time, gyro_valley))
            
            # 存储导数值
            acc_diff.append(curr_acc_diff)
            gyro_diff.append(curr_gyro_diff)
            filtered_acc_diff.append(curr_filtered_acc_diff)
            filtered_gyro_diff.append(curr_filtered_gyro_diff)
        else:  # 第一个点的导数设为0
            acc_diff.append(0)
            gyro_diff.append(0)
            filtered_acc_diff.append(0)
            filtered_gyro_diff.append(0)

def animate(frame):
    update_plot_data()
    
    if not timestamps:
        return lines_acc + lines_gyro
    
    relative_times = list(timestamps)
    
    # 更新x轴范围
    current_time = relative_times[-1]
    window_size = 3.0  # 3秒窗口
    start_time = max(0, current_time - window_size)
    
    # 动态更新x轴
    padding = window_size * 0.1
    ax1.set_xlim(start_time - padding, current_time + padding)
    ax2.set_xlim(start_time - padding, current_time + padding)
    
    # 获取当前窗口内的数据
    window_indices = [i for i, t in enumerate(relative_times) if t >= start_time]
    if window_indices:
        # 更新y轴范围
        window_acc_diff = [acc_diff[i] for i in window_indices]
        window_acc_diff_filtered = [filtered_acc_diff[i] for i in window_indices]
        if window_acc_diff:
            acc_min, acc_max = min(window_acc_diff), max(window_acc_diff)
            acc_padding = (acc_max - acc_min) * 0.1
            ax1.set_ylim(acc_min - acc_padding, acc_max + acc_padding)
        
        window_gyro_diff = [gyro_diff[i] for i in window_indices]
        window_gyro_diff_filtered = [filtered_gyro_diff[i] for i in window_indices]
        if window_gyro_diff:
            gyro_min, gyro_max = min(gyro_diff), max(gyro_diff)
            gyro_padding = (gyro_max - gyro_min) * 0.1
            ax2.set_ylim(gyro_min - gyro_padding, gyro_max + gyro_padding)
    
    # 更新数据
    lines_acc[0].set_data(relative_times, list(acc_diff))  # 原始norm
    lines_acc[1].set_data(relative_times[1:], list(filtered_acc_diff)[1:])  # 滤波后的导数，跳过第一个点
    lines_gyro[0].set_data(relative_times, list(gyro_diff))  # 原始norm
    lines_gyro[1].set_data(relative_times[1:], list(filtered_gyro_diff)[1:])  # 滤波后的导数，跳过第一个点
    
    # 清除之前的peak和valley标记
    for artist in ax1.lines[2:]:
        artist.remove()
    for artist in ax2.lines[2:]:
        artist.remove()
    
    # 添加peak和valley标记
    for peak_time, peak_val in acc_peaks:
        if start_time <= peak_time <= current_time:
            ax1.plot(peak_time, peak_val, 'ro', markersize=8)
    for valley_time, valley_val in acc_valleys:
        if start_time <= valley_time <= current_time:
            ax1.plot(valley_time, valley_val, 'yo', markersize=8)
    
    for peak_time, peak_val in gyro_peaks:
        if start_time <= peak_time <= current_time:
            ax2.plot(peak_time, peak_val, 'ro', markersize=8)
    for valley_time, valley_val in gyro_valleys:
        if start_time <= valley_time <= current_time:
            ax2.plot(valley_time, valley_val, 'yo', markersize=8)
    
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