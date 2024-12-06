import socket
import json
import threading
import time
import pandas as pd
import numpy as np
from datetime import datetime
from collections import deque
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
import os

class SensorDataServer:
    def __init__(self, host='0.0.0.0', port=12345):
        self.host = host
        self.port = port
        self.server_socket = None
        self.client_socket = None
        self.running = False
        self.data_buffer = deque(maxlen=1000)  # 限制缓冲区大小
        self.lock = threading.Lock()
        
        # 用于实时绘图的数据
        self.time_window = 500  # 显示最近500个数据点
        self.timestamps = []
        self.acc_data = {'x': [], 'y': [], 'z': []}
        self.gyro_data = {'x': [], 'y': [], 'z': []}
        
        # 创建数据保存目录
        self.data_dir = os.path.join(os.path.dirname(__file__), 'data')
        os.makedirs(self.data_dir, exist_ok=True)
        
        # 设置socket选项
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)  # 禁用Nagle算法
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)  # 增加接收缓冲区
        
        # 创建实时绘图窗口
        self.setup_plot()
        
    def setup_plot(self):
        self.fig, (self.ax1, self.ax2) = plt.subplots(2, 1, figsize=(12, 8))
        self.fig.suptitle('实时传感器数据')
        
        # 加速度计图表
        self.acc_lines = {
            'x': self.ax1.plot([], [], 'r-', label='X')[0],
            'y': self.ax1.plot([], [], 'g-', label='Y')[0],
            'z': self.ax1.plot([], [], 'b-', label='Z')[0]
        }
        self.ax1.set_title('加速度计数据')
        self.ax1.set_ylabel('加速度 (m/s²)')
        self.ax1.legend()
        self.ax1.grid(True)
        
        # 陀螺仪图表
        self.gyro_lines = {
            'x': self.ax2.plot([], [], 'r-', label='X')[0],
            'y': self.ax2.plot([], [], 'g-', label='Y')[0],
            'z': self.ax2.plot([], [], 'b-', label='Z')[0]
        }
        self.ax2.set_title('陀螺仪数据')
        self.ax2.set_ylabel('角速度 (rad/s)')
        self.ax2.legend()
        self.ax2.grid(True)
        
        # 启动动画
        self.ani = FuncAnimation(self.fig, self.update_plot, interval=50)
        plt.show(block=False)
    
    def update_plot(self, frame):
        with self.lock:
            if len(self.timestamps) > self.time_window:
                start_idx = -self.time_window
            else:
                start_idx = 0
                
            x_data = range(len(self.timestamps[start_idx:]))
            
            # 更新加速度计数据
            for axis in ['x', 'y', 'z']:
                self.acc_lines[axis].set_data(x_data, self.acc_data[axis][start_idx:])
            self.ax1.relim()
            self.ax1.autoscale_view()
            
            # 更新陀螺仪数据
            for axis in ['x', 'y', 'z']:
                self.gyro_lines[axis].set_data(x_data, self.gyro_data[axis][start_idx:])
            self.ax2.relim()
            self.ax2.autoscale_view()
            
            return self.acc_lines.values(), self.gyro_lines.values()
    
    def start(self):
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)
        self.running = True
        
        print(f"服务器启动在 {self.host}:{self.port}")
        
        # 启动数据保存线程
        save_thread = threading.Thread(target=self.save_data_periodically)
        save_thread.daemon = True
        save_thread.start()
        
        while self.running:
            try:
                print("等待客户端连接...")
                self.client_socket, addr = self.server_socket.accept()
                print(f"客户端已连接: {addr}")
                
                self.handle_client()
            except Exception as e:
                print(f"连接错误: {e}")
                if self.client_socket:
                    self.client_socket.close()
    
    def handle_client(self):
        buffer = ""
        self.client_socket.settimeout(0.1)  # 设置超时，避免阻塞
        
        while self.running:
            try:
                data = self.client_socket.recv(8192)  # 增加接收缓冲区
                if not data:
                    break
                
                buffer += data.decode('utf-8')
                
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    try:
                        sensor_data = json.loads(line)
                        with self.lock:
                            self.process_sensor_data(sensor_data)
                    except json.JSONDecodeError:
                        continue
                    
            except socket.timeout:
                continue
            except Exception as e:
                print(f"数据接收错误: {e}")
                break
        
        self.client_socket.close()
    
    def process_sensor_data(self, data):
        # 添加时间戳
        data['received_time'] = datetime.now().isoformat()
        self.data_buffer.append(data)
        
        # 更新绘图数据
        self.timestamps.append(data['timestamp'])
        self.acc_data['x'].append(data['acc_x'])
        self.acc_data['y'].append(data['acc_y'])
        self.acc_data['z'].append(data['acc_z'])
        self.gyro_data['x'].append(data['gyro_x'])
        self.gyro_data['y'].append(data['gyro_y'])
        self.gyro_data['z'].append(data['gyro_z'])
        
        # 保持数据长度在时间窗口范围内
        if len(self.timestamps) > self.time_window:
            self.timestamps = self.timestamps[-self.time_window:]
            for axis in ['x', 'y', 'z']:
                self.acc_data[axis] = self.acc_data[axis][-self.time_window:]
                self.gyro_data[axis] = self.gyro_data[axis][-self.time_window:]
        
        print(f"收到数据: Acc(x={data['acc_x']:.2f}, y={data['acc_y']:.2f}, z={data['acc_z']:.2f}) "
              f"Gyro(x={data['gyro_x']:.2f}, y={data['gyro_y']:.2f}, z={data['gyro_z']:.2f})")
    
    def save_data_periodically(self):
        last_save_time = time.time()
        
        while self.running:
            current_time = time.time()
            if current_time - last_save_time >= 5 and self.data_buffer:  # 每5秒保存一次
                with self.lock:
                    df = pd.DataFrame(list(self.data_buffer))
                    filename = os.path.join(self.data_dir, 
                                         f"sensor_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv")
                    df.to_csv(filename, index=False)
                    print(f"数据已保存到 {filename}")
                    self.data_buffer.clear()
                last_save_time = current_time
            
            time.sleep(0.1)  # 降低CPU使用率
    
    def stop(self):
        self.running = False
        if self.client_socket:
            self.client_socket.close()
        if self.server_socket:
            self.server_socket.close()
        plt.close('all')

if __name__ == "__main__":
    server = SensorDataServer()
    try:
        server.start()
    except KeyboardInterrupt:
        print("\n正在停止服务器...")
        server.stop()