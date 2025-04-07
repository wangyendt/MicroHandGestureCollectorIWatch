import numpy as np
import coremltools as ct
import os
import sys
from scipy.signal import butter

# Make sure the path to butterworth_filter is correct
try:
    sys.path.append('../pybind_libs/detrend_iir')
    from butterworth_filter import ButterworthFilter
except ImportError:
    print("Error: Could not import ButterworthFilter.")
    print("Please ensure '../pybind_libs/detrend_iir' is in the Python path and the module exists.")
    sys.exit(1)


class MLPackageInference:
    def __init__(self, model_path):
        """
        初始化MLPackage推理类
        Args:
            model_path: mlpackage文件的路径
        """
        try:
            self.model = ct.models.MLModel(model_path)
            self.input_desc = self.model.input_description
            self.output_desc = self.model.output_description
            # 打印模型输入输出信息
            print("\n模型信息:")
            print(f"模型路径: {model_path}")
            print(f"输入描述: {self.input_desc}")
            print(f"输出描述: {self.output_desc}\n")
        except Exception as e:
            print(f"加载模型失败: {model_path}")
            print(f"错误: {e}")
            sys.exit(1)

    def preprocess(self, input_data):
        """
        预处理输入数据
        """
        # 确保数据类型正确
        input_data = np.asarray(input_data).astype(np.float32)
        # print(f"输入数据形状: {input_data.shape}")
        # print(f"输入数据类型: {input_data.dtype}")
        return input_data

    def predict(self, input_data):
        """
        使用模型进行推理
        """
        processed_data = self.preprocess(input_data)
        # 直接使用已知的输入特征名称 "input"
        input_key = "input"
        input_dict = {input_key: processed_data}

        try:
            predictions = self.model.predict(input_dict)
            # print(f"预测结果类型: {type(predictions)}")
            # if isinstance(predictions, dict):
            #     print(f"预测结果键: {predictions.keys()}")
            return predictions
        except Exception as e:
            print(f"模型推理出错: {e}")
            # 返回None或引发异常，取决于错误处理策略
            return None


def load_config():
    """加载模型参数和手势标签"""
    # 注意：wayne_gestures 需要根据实际情况填充
    wayne_gestures = ["手势1", "手势2", "手势3", "手势4", "手势5", "手势6"] # 示例，请替换
    haili_gestures = ["单击", "双击", "左摆", "右摆", "握拳", "摊掌", "反掌", "转腕", "旋腕", "日常"]

    gesture_map = {
        'wayne': wayne_gestures,
        'haili': haili_gestures
    }

    params = {
        'wayne': {
            'half_window_size': 30,
            'model_path': '/Users/wayne/Documents/work/code/project/ffalcon/micro-hand-gesture/MicroHandGestureCollectorIWatch/MicroHandGestureCollectorIWatch Watch App/GestureClassifier.mlpackage',
            'shape': (1, 6, 60) # (batch, channels, sequence_length)
        },
        'haili': {
            'half_window_size': 50,
            'model_path': '/Users/wayne/Documents/work/code/project/ffalcon/micro-hand-gesture/MicroHandGestureCollectorIWatch/MicroHandGestureCollectorIWatch Watch App/GestureModel_1.mlpackage',
            # haili模型的shape需要确认，原始代码是 (1, 6, 4, 100)
            # 如果模型输入是 (batch, channels, frequency_bands, time_steps)
            'shape': (1, 6, 4, 100)
        }
    }
    return params, gesture_map


def load_sensor_data(root_dir):
    """加载传感器数据和结果时间戳"""
    acc_path = os.path.join(root_dir, 'acc.txt')
    gyro_path = os.path.join(root_dir, 'gyro.txt')
    result_path = os.path.join(root_dir, 'result.txt')

    if not all(os.path.exists(p) for p in [acc_path, gyro_path, result_path]):
        print(f"错误：在 {root_dir} 中找不到所需的数据文件 (acc.txt, gyro.txt, result.txt)")
        sys.exit(1)

    try:
        acc_data = np.loadtxt(acc_path, skiprows=1, delimiter=',')
        gyro_data = np.loadtxt(gyro_path, skiprows=1, delimiter=',')
        with open(result_path, encoding='utf-8', mode='r') as f:
            lines = f.readlines()[1:]
            result_timestamps = [int(line.strip().split(',')[0]) for line in lines]

        # 查找时间戳对应的索引
        # 使用 searchsorted 提高效率，假设时间戳是大致排序的
        acc_timestamps = acc_data[:, 0]
        acc_peak_indices = np.searchsorted(acc_timestamps, result_timestamps)
        # 验证找到的索引对应的时间戳是否足够接近
        valid_indices = []
        for i, target_ts in enumerate(result_timestamps):
             actual_ts = acc_timestamps[acc_peak_indices[i]]
             # 可以设置一个小的容差，例如 10ms (假设采样率100Hz)
             if abs(actual_ts - target_ts) <= 10:
                 valid_indices.append(acc_peak_indices[i])
             else:
                 # 如果找不到精确匹配，可以尝试查找最近的索引
                 closest_idx = np.argmin(np.abs(acc_timestamps - target_ts))
                 if abs(acc_timestamps[closest_idx] - target_ts) <= 10:
                     valid_indices.append(closest_idx)
                 else:
                      print(f"警告：无法为时间戳 {target_ts} 找到足够接近的索引。最近的是 {acc_timestamps[closest_idx]}")

        # 确保索引不会导致切片越界
        min_idx = params[whose_model]['half_window_size']
        max_idx = len(acc_data) - params[whose_model]['half_window_size']
        valid_indices = [idx for idx in valid_indices if min_idx <= idx < max_idx]

        if not valid_indices:
             print("错误：未能根据 result.txt 中的时间戳找到任何有效的峰值索引。")
             sys.exit(1)


        return acc_data, gyro_data, np.array(valid_indices)

    except Exception as e:
        print(f"加载或处理数据时出错: {e}")
        sys.exit(1)


def create_butterworth_filters(fs=100.0):
    """创建巴特沃斯滤波器"""
    nyquist = fs / 2.0
    try:
        b_low, a_low = butter(N=2, Wn=[0.25 / nyquist, 8.0 / nyquist], btype='bandpass')
        b_mid, a_mid = butter(N=2, Wn=[8.0 / nyquist, 32.0 / nyquist], btype='bandpass')
        b_high, a_high = butter(N=2, Wn=[32.0 / nyquist], btype='highpass')

        bwf_low = ButterworthFilter(b_low, a_low)
        bwf_mid = ButterworthFilter(b_mid, a_mid)
        bwf_high = ButterworthFilter(b_high, a_high)
        return bwf_low, bwf_mid, bwf_high
    except Exception as e:
        print(f"创建滤波器时出错: {e}")
        sys.exit(1)


def extract_and_process_segment(idx, acc_data, gyro_data, params, whose_model, bwf_low, bwf_mid, bwf_high):
    """提取、滤波并组合单个数据段"""
    half_window = params[whose_model]['half_window_size']
    start, end = idx - half_window, idx + half_window

    acc_segment = acc_data[start:end, 1:] # 取 X, Y, Z 列
    gyro_segment = gyro_data[start:end, 1:] # 取 X, Y, Z 列

    # 应用滤波器
    acc_low = np.apply_along_axis(lambda x: bwf_low.filter(x.tolist()), 0, acc_segment)
    gyro_low = np.apply_along_axis(lambda x: bwf_low.filter(x.tolist()), 0, gyro_segment)
    acc_mid = np.apply_along_axis(lambda x: bwf_mid.filter(x.tolist()), 0, acc_segment)
    gyro_mid = np.apply_along_axis(lambda x: bwf_mid.filter(x.tolist()), 0, gyro_segment)
    acc_high = np.apply_along_axis(lambda x: bwf_high.filter(x.tolist()), 0, acc_segment)
    gyro_high = np.apply_along_axis(lambda x: bwf_high.filter(x.tolist()), 0, gyro_segment)

    # 组合特征 - 注意根据模型输入调整组合方式
    # Haili 模型需要 (batch, channels, bands, time_steps) = (1, 6, 4, 100)
    if whose_model == 'haili':
        # 原始信号 (Acc+Gyro), 低频, 中频, 高频
        # Stack along a new 'band' dimension (axis=0 before transpose)
        processed_data = np.stack([
            np.c_[acc_segment / 9.81, gyro_segment], # Band 0: Raw
            np.c_[acc_low / 9.81, gyro_low],         # Band 1: Low Freq
            np.c_[acc_mid / 9.81, gyro_mid],         # Band 2: Mid Freq
            np.c_[acc_high / 9.81, gyro_high]        # Band 3: High Freq
        ], axis=0) # Shape: (bands, time_steps, channels) = (4, 100, 6)

        # Transpose to (channels, bands, time_steps) = (6, 4, 100)
        processed_data = np.transpose(processed_data, (2, 0, 1))

        # Add batch dimension: (1, 6, 4, 100)
        processed_data = processed_data[None, ...]


    elif whose_model == 'wayne':
         # Wayne 模型需要 (batch, channels, time_steps) = (1, 6, 60)
         # 假设 Wayne 模型只使用原始信号
         processed_data = np.c_[acc_segment / 9.81, gyro_segment] # Shape: (time_steps, channels) = (60, 6)
         # Transpose to (channels, time_steps) = (6, 60)
         processed_data = processed_data.T
         # Add batch dimension: (1, 6, 60)
         processed_data = processed_data[None, ...]
    else:
        raise ValueError(f"未知的模型类型: {whose_model}")


    # 验证形状是否匹配
    expected_shape = params[whose_model]['shape']
    if processed_data.shape != expected_shape:
        print(f"警告：处理后的数据形状 {processed_data.shape} 与预期形状 {expected_shape} 不符。")
        # 可能需要根据具体模型调整处理逻辑

    return processed_data


def run_inference(inferencer, data_segment, gesture_map, whose_model):
    """执行推理并打印结果"""
    try:
        result = inferencer.predict(data_segment)
        if result is None:
            print("推理失败，跳过此段。")
            return

        # 直接使用已知的输出特征名称 "output"
        output_key = "output"
        if output_key not in result:
            print(f"错误：预测结果中找不到预期的输出键 '{output_key}'。可用键: {result.keys()}")
            # 尝试使用字典中的第一个键作为后备
            if result:
                 output_key = list(result.keys())[0]
                 print(f"将尝试使用键: '{output_key}'")
            else:
                 print("预测结果字典为空。")
                 return


        probabilities = result[output_key]

        # 处理可能的嵌套或批处理维度
        if probabilities.ndim > 1:
             probabilities = probabilities.squeeze() # 移除批次或不必要的维度


        if probabilities.ndim != 1:
             print(f"错误：处理后的概率向量维度不为1 (shape: {probabilities.shape})。原始结果: {result}")
             return


        predicted_index = np.argmax(probabilities)
        gesture_labels = gesture_map.get(whose_model)

        if gesture_labels and 0 <= predicted_index < len(gesture_labels):
            predicted_gesture = gesture_labels[predicted_index]
            confidence = probabilities[predicted_index]
            print(f"预测手势: {predicted_gesture} (索引: {predicted_index}, 置信度: {confidence:.4f})")
            # print(f"完整概率: {probabilities}") # 可选：打印完整概率向量
        else:
            print(f"错误：预测索引 {predicted_index} 超出标签范围 {len(gesture_labels) if gesture_labels else 'N/A'} 或未找到 '{whose_model}' 的手势标签。")
            print(f"原始概率: {probabilities}")


    except Exception as e:
        print(f"执行推理或解析结果时出错: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    # --- 配置 ---
    whose_model = 'haili'  # 或者 'wayne'
    # 数据根目录，根据需要修改
    root = '/Users/wayne/Downloads/2025_04_07_14_52_02_Howie_左手_混合_轻_静坐'

    # --- 加载配置和数据 ---
    params, gesture_map = load_config()
    acc_data, gyro_data, acc_peak_indices = load_sensor_data(root)
    bwf_low, bwf_mid, bwf_high = create_butterworth_filters()

    # --- 初始化模型 ---
    model_path = params[whose_model]['model_path']
    inferencer = MLPackageInference(model_path)

    print(f"\n开始处理 {len(acc_peak_indices)} 个峰值...")
    # --- 循环处理每个峰值 ---
    for i, idx in enumerate(acc_peak_indices):
        print(f"\n--- 处理峰值 {i+1}/{len(acc_peak_indices)} (原始索引: {idx}) ---")
        try:
            # 提取和处理数据段
            data_segment = extract_and_process_segment(
                idx, acc_data, gyro_data, params, whose_model, bwf_low, bwf_mid, bwf_high
            )

            # 执行推理并打印结果
            run_inference(inferencer, data_segment, gesture_map, whose_model)

        except Exception as e:
            print(f"处理索引 {idx} 时发生意外错误: {e}")
            import traceback
            traceback.print_exc() # 打印详细错误信息

    print("\n处理完成。")
