import socket
import json
import csv
from datetime import datetime
import os

def setup_server(host='0.0.0.0', port=12345):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((host, port))
    server_socket.listen(1)
    print(f"服务器正在监听 {host}:{port}")
    return server_socket

def process_data(data_str):
    try:
        data = json.loads(data_str)
        if data.get("type") == "batch_data":
            batch_data = data.get("data", [])
            if batch_data and isinstance(batch_data, list):
                processed_batch = []
                for item in batch_data:
                    timestamp_ns = item.get("timestamp", 0)
                    acc_x = item.get("acc_x", 0)
                    acc_y = item.get("acc_y", 0)
                    acc_z = item.get("acc_z", 0)
                    gyro_x = item.get("gyro_x", 0)
                    gyro_y = item.get("gyro_y", 0)
                    gyro_z = item.get("gyro_z", 0)
                    
                    processed_batch.append((timestamp_ns, acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z))
                
                print(f"Processed batch of {len(processed_batch)} data points")
                return processed_batch
                
        elif data.get("type") == "stop_collection":
            print("收到停止采集信号")
            return None
        print("Unexpected data type:", data.get("type"))
    except json.JSONDecodeError as e:
        print("JSON parsing error:", e)
    return None

def save_to_csv(data_points, filename):
    os.makedirs("data", exist_ok=True)
    filepath = os.path.join("data", filename)
    
    with open(filepath, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        # 写入CSV头部
        writer.writerow([
            "timestamp_ns",  # iWatch采集时间戳（纳秒）
            # "timestamp",     # 人类可读时间
            "acc_x", "acc_y", "acc_z",
            "gyro_x", "gyro_y", "gyro_z"
        ])
        
        # 写入数据
        for point in data_points:
            timestamp_ns, acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z = point
            # 将纳秒时间戳转换为人类可读格式
            # timestamp = datetime.fromtimestamp(timestamp_ns / 1_000_000_000)
            writer.writerow([
                timestamp_ns,
                # timestamp.strftime('%Y-%m-%d %H:%M:%S.%f'),
                acc_x, acc_y, acc_z,
                gyro_x, gyro_y, gyro_z
            ])
    print(f"数据已保存到 {filepath}")

def main():
    server_socket = setup_server()
    current_data_points = []
    
    try:
        while True:
            print("等待连接...")
            client_socket, address = server_socket.accept()
            print(f"接受来自 {address} 的连接")
            
            buffer = ""
            start_time = datetime.now()
            
            try:
                while True:
                    data = client_socket.recv(1024).decode('utf-8')
                    if not data:
                        break
                    
                    buffer += data
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        processed_data = process_data(line)
                        if processed_data:
                            if isinstance(processed_data, list):
                                # 处理批量数据
                                current_data_points.extend(processed_data)
                                print(f"Added {len(processed_data)} points, total: {len(current_data_points)}")
                            
                    # 每隔一定时间保存数据
                    if (datetime.now() - start_time).seconds >= 60:
                        if current_data_points:
                            filename = f"sensor_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
                            save_to_csv(current_data_points, filename)
                            current_data_points = []
                            start_time = datetime.now()
                            
            except Exception as e:
                print(f"处理数据时出错: {e}")
                print(f"错误详情: {str(e)}")
                import traceback
                traceback.print_exc()
            finally:
                if current_data_points:
                    filename = f"sensor_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
                    save_to_csv(current_data_points, filename)
                    current_data_points = []
                client_socket.close()
                
    except KeyboardInterrupt:
        print("\n服务器关闭")
    finally:
        if current_data_points:
            filename = f"sensor_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
            save_to_csv(current_data_points, filename)
        server_socket.close()

if __name__ == "__main__":
    main()