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

class MotionDataVisualizer:
    def __init__(self):
        # 常量定义
        self.WINDOW_SIZE = 1000  # 10秒数据，100Hz
        self.PLOT_INTERVAL = 10
        self.FPS = 60
        self.PEAK_DELTA = 0.3  # peak detection的阈值
        self.SAMPLE_TIME = 0.01  # 采样时间(100Hz)

        # 数据队列
        self.timestamps = deque(maxlen=self.WINDOW_SIZE)
        self.acc_norm = deque(maxlen=self.WINDOW_SIZE)
        self.gyro_norm = deque(maxlen=self.WINDOW_SIZE)
        self.acc_diff = deque(maxlen=self.WINDOW_SIZE)
        self.gyro_diff = deque(maxlen=self.WINDOW_SIZE)
        self.filtered_acc_diff = deque(maxlen=self.WINDOW_SIZE)
        self.filtered_gyro_diff = deque(maxlen=self.WINDOW_SIZE)

        # Peak detection状态
        self.acc_lookformax = True
        self.gyro_lookformax = True
        self.acc_mn, self.acc_mx = np.Inf, -np.Inf
        self.gyro_mn, self.gyro_mx = np.Inf, -np.Inf
        self.acc_peaks = deque(maxlen=100)
        self.acc_valleys = deque(maxlen=100)
        self.gyro_peaks = deque(maxlen=100)
        self.gyro_valleys = deque(maxlen=100)

        # 时间戳相关
        self.first_timestamp = None
        self.acc_mx_time, self.acc_mn_time = 0, 0
        self.gyro_mx_time, self.gyro_mn_time = 0, 0

        # 滤波器
        self.acc_filter = OneEuroFilter(te=self.SAMPLE_TIME, mincutoff=10.0, beta=0.001, dcutoff=1.0)
        self.gyro_filter = OneEuroFilter(te=self.SAMPLE_TIME, mincutoff=10.0, beta=0.001, dcutoff=1.0)

        # 数据缓冲
        self.data_buffer = queue.Queue()

        # 创建图形
        self.setup_plot()

    def setup_plot(self):
        plt.style.use('dark_background')
        self.fig = plt.figure(figsize=(12, 8))
        self.ax1 = plt.subplot(211)
        self.ax2 = plt.subplot(212)
        self.lines_acc = []
        self.lines_gyro = []

    def init_plot(self):
        # 初始化图表...（与原init函数相同，但使用self.属性）
        self.ax1.set_title('Accelerometer Norm')
        self.ax1.set_ylabel('Total Acceleration (m/s²)')
        self.ax1.grid(True, alpha=0.2)
        
        self.ax2.set_title('Gyroscope Norm')
        self.ax2.set_xlabel('Time (s)')
        self.ax2.set_ylabel('Angular Velocity (rad/s)')
        self.ax2.grid(True, alpha=0.2)
        
        colors = ['#FF9F1C', '#4ECDC4']
        for ax in [self.ax1, self.ax2]:
            lines = []
            line, = ax.plot([], [], label='Original', color=colors[0], linewidth=1, alpha=0.5)
            lines.append(line)
            line, = ax.plot([], [], label='Filtered', color=colors[1], linewidth=2)
            lines.append(line)
            ax.legend(loc='upper right')
            if ax == self.ax1:
                self.lines_acc.extend(lines)
            else:
                self.lines_gyro.extend(lines)
        
        self.ax1.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f"{x:.3f}s"))
        self.ax2.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f"{x:.3f}s"))
        
        return self.lines_acc + self.lines_gyro

    def update_plot_data(self):
        points_to_add = min(self.PLOT_INTERVAL, self.data_buffer.qsize())
        last_timestamp = None
        
        for _ in range(points_to_add):
            if self.data_buffer.empty():
                break
                
            point = self.data_buffer.get()
            current_timestamp = point['timestamp']
            
            if self.first_timestamp is None:
                self.first_timestamp = current_timestamp
                
            rel_time = (current_timestamp - self.first_timestamp) / 1_000_000_000.0
            
            te = self.SAMPLE_TIME if last_timestamp is None else (current_timestamp - last_timestamp) / 1_000_000_000.0
            last_timestamp = current_timestamp
            
            # 处理数据...（与原update_plot_data函数相同，但使用self.属性）
            self._process_point(point, rel_time, te)

    def _process_point(self, point, rel_time, te):
        # 提取原update_plot_data中的数据处理逻辑...
        acc_norm_val = np.sqrt(point['acc_x']**2 + point['acc_y']**2 + point['acc_z']**2)
        gyro_norm_val = np.sqrt(point['gyro_x']**2 + point['gyro_y']**2 + point['gyro_z']**2)
        
        self.timestamps.append(rel_time)
        self.acc_norm.append(acc_norm_val)
        self.gyro_norm.append(gyro_norm_val)
        
        if len(self.acc_norm) > 1:
            self._process_derivatives(rel_time, te)
        else:
            self.acc_diff.append(0)
            self.gyro_diff.append(0)
            self.filtered_acc_diff.append(0)
            self.filtered_gyro_diff.append(0)

    def _process_derivatives(self, rel_time, te):
        curr_acc_diff = abs(self.acc_norm[-1] - self.acc_norm[-2])
        curr_gyro_diff = abs(self.gyro_norm[-1] - self.gyro_norm[-2])
        
        curr_filtered_acc_diff = self.acc_filter.apply(curr_acc_diff, te)
        curr_filtered_gyro_diff = self.gyro_filter.apply(curr_gyro_diff, te)
        
        # Peak detection使用滤波后的导数
        (acc_peak, acc_peak_time, acc_valley, acc_valley_time, 
         self.acc_lookformax, self.acc_mn, self.acc_mx, 
         self.acc_mn_time, self.acc_mx_time,
         is_acc_peak, is_acc_valley) = self._online_peak_detection(
            curr_filtered_acc_diff, rel_time, self.acc_lookformax, 
            self.acc_mn, self.acc_mx, self.acc_mn_time, self.acc_mx_time, 
            self.PEAK_DELTA)
        
        (gyro_peak, gyro_peak_time, gyro_valley, gyro_valley_time,
         self.gyro_lookformax, self.gyro_mn, self.gyro_mx, 
         self.gyro_mn_time, self.gyro_mx_time,
         is_gyro_peak, is_gyro_valley) = self._online_peak_detection(
            curr_filtered_gyro_diff, rel_time, self.gyro_lookformax,
            self.gyro_mn, self.gyro_mx, self.gyro_mn_time, self.gyro_mx_time, 
            self.PEAK_DELTA)
        
        # 存储peaks和valleys
        if is_acc_peak:
            self.acc_peaks.append((acc_peak_time, acc_peak))
        if is_acc_valley:
            self.acc_valleys.append((acc_valley_time, acc_valley))
        if is_gyro_peak:
            self.gyro_peaks.append((gyro_peak_time, gyro_peak))
        if is_gyro_valley:
            self.gyro_valleys.append((gyro_valley_time, gyro_valley))
        
        # 存储导数值
        self.acc_diff.append(curr_acc_diff)
        self.gyro_diff.append(curr_gyro_diff)
        self.filtered_acc_diff.append(curr_filtered_acc_diff)
        self.filtered_gyro_diff.append(curr_filtered_gyro_diff)

    def _online_peak_detection(self, value, timestamp, lookformax, mn, mx, mn_time, mx_time, delta):
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
                
        return (peak, peak_time, valley, valley_time, lookformax, 
                mn, mx, mn_time, mx_time, is_peak, is_valley)

    def animate(self, frame):
        self.update_plot_data()
        
        if not self.timestamps:
            return self.lines_acc + self.lines_gyro
        
        relative_times = list(self.timestamps)
        
        # 更新x轴范围
        current_time = relative_times[-1]
        window_size = 3.0  # 3秒窗口
        start_time = max(0, current_time - window_size)
        
        # 动态更新x轴
        padding = window_size * 0.1
        self.ax1.set_xlim(start_time - padding, current_time + padding)
        self.ax2.set_xlim(start_time - padding, current_time + padding)
        
        # 获取当前窗口内的数据
        window_indices = [i for i, t in enumerate(relative_times) if t >= start_time]
        if window_indices:
            # 更新y轴范围
            window_acc_diff = [self.acc_diff[i] for i in window_indices]
            window_acc_diff_filtered = [self.filtered_acc_diff[i] for i in window_indices]
            if window_acc_diff:
                acc_min, acc_max = min(window_acc_diff), max(window_acc_diff)
                acc_padding = (acc_max - acc_min) * 0.1
                self.ax1.set_ylim(acc_min - acc_padding, acc_max + acc_padding)
            
            window_gyro_diff = [self.gyro_diff[i] for i in window_indices]
            window_gyro_diff_filtered = [self.filtered_gyro_diff[i] for i in window_indices]
            if window_gyro_diff:
                gyro_min, gyro_max = min(self.gyro_diff), max(self.gyro_diff)
                gyro_padding = (gyro_max - gyro_min) * 0.1
                self.ax2.set_ylim(gyro_min - gyro_padding, gyro_max + gyro_padding)
        
        # 更新数据
        self.lines_acc[0].set_data(relative_times, list(self.acc_diff))
        self.lines_acc[1].set_data(relative_times[1:], list(self.filtered_acc_diff)[1:])
        self.lines_gyro[0].set_data(relative_times, list(self.gyro_diff))
        self.lines_gyro[1].set_data(relative_times[1:], list(self.filtered_gyro_diff)[1:])
        
        # 清除之前的peak和valley标记
        for artist in self.ax1.lines[2:]:
            artist.remove()
        for artist in self.ax2.lines[2:]:
            artist.remove()
        
        # 添加peak和valley标记
        for peak_time, peak_val in self.acc_peaks:
            if start_time <= peak_time <= current_time:
                self.ax1.plot(peak_time, peak_val, 'ro', markersize=8)
        for valley_time, valley_val in self.acc_valleys:
            if start_time <= valley_time <= current_time:
                self.ax1.plot(valley_time, valley_val, 'yo', markersize=8)
        
        for peak_time, peak_val in self.gyro_peaks:
            if start_time <= peak_time <= current_time:
                self.ax2.plot(peak_time, peak_val, 'ro', markersize=8)
        for valley_time, valley_val in self.gyro_valleys:
            if start_time <= valley_time <= current_time:
                self.ax2.plot(valley_time, valley_val, 'yo', markersize=8)
        
        return self.lines_acc + self.lines_gyro

    def run(self):
        server_socket = self.setup_socket()
        
        receiver_thread = threading.Thread(target=self.data_receiver, args=(server_socket,))
        receiver_thread.daemon = True
        receiver_thread.start()
        
        ani = animation.FuncAnimation(
            self.fig, self.animate, init_func=self.init_plot,
            interval=1000/self.FPS,
            blit=False
        )
        
        plt.tight_layout()
        plt.show()

    @staticmethod
    def setup_socket():
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(('0.0.0.0', 12345))
        server_socket.listen(1)
        print("等待连接...")
        return server_socket

    def data_receiver(self, server_socket):
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
                        self.process_data(line)
            except Exception as e:
                print(f"接收数据错误: {e}")
            finally:
                client_socket.close()

    def process_data(self, data_str):
        try:
            data = json.loads(data_str)
            if data.get("type") == "batch_data":
                batch_data = data.get("data", [])
                if batch_data and isinstance(batch_data, list):
                    for item in batch_data:
                        point_data = {
                            'timestamp': item.get("timestamp", 0),
                            'acc_x': item.get("acc_x", 0),
                            'acc_y': item.get("acc_y", 0),
                            'acc_z': item.get("acc_z", 0),
                            'gyro_x': item.get("gyro_x", 0),
                            'gyro_y': item.get("gyro_y", 0),
                            'gyro_z': item.get("gyro_z", 0)
                        }
                        self.data_buffer.put(point_data)
        except json.JSONDecodeError as e:
            print("JSON parsing error:", e)

def main():
    visualizer = MotionDataVisualizer()
    visualizer.run()

if __name__ == "__main__":
    main()