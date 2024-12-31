import numpy as np
from butterworth_filter import ButterworthFilter

def test_filter():
    # 创建一个测试信号
    t = np.linspace(0, 1, 1000)
    signal = np.sin(2 * np.pi * 10 * t) + 0.5 * np.sin(2 * np.pi * 50 * t)
    
    # Butterworth滤波器系数 (这里使用一个简单的低通滤波器示例)
    b = [0.0675, 0.1349, 0.0675]
    a = [1.0, -1.1430, 0.4128]
    
    # 创建滤波器实例
    filter = ButterworthFilter(b, a)
    
    # 应用滤波器
    filtered_signal = filter.filter(signal.tolist())
    
    print("原始信号长度:", len(signal))
    print("滤波后信号长度:", len(filtered_signal))
    print("滤波后前5个值:", filtered_signal[:5])

if __name__ == "__main__":
    test_filter()