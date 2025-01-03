import numpy as np
import coremltools as ct
import os

class MLPackageInference:
    def __init__(self, model_path):
        """
        初始化MLPackage推理类
        Args:
            model_path: mlpackage文件的路径
        """
        self.model = ct.models.MLModel(model_path)
        self.input_desc = self.model.input_description
        self.output_desc = self.model.output_description
        
        # 打印模型输入输出信息
        print("\n模型信息:")
        print(f"输入描述: {self.input_desc}")
        print(f"输出描述: {self.output_desc}\n")
        
    def preprocess(self, input_data):
        """
        预处理输入数据
        Args:
            input_data: numpy数组格式的输入数据，期望维度为(batch_size, channels, height, width)
        Returns:
            处理后的数据
        """
        # 确保数据类型正确
        input_data = np.asarray(input_data).astype(np.float32)
        
        # 打印输入数据的形状和类型，帮助调试
        print(f"输入数据形状: {input_data.shape}")
        print(f"输入数据类型: {input_data.dtype}")
        
        return input_data

    def predict(self, input_data):
        """
        使用模型进行推理
        Args:
            input_data: 输入数据
        Returns:
            模型预测结果
        """
        # 预处理数据
        processed_data = self.preprocess(input_data)
        
        # 准备输入字典，使用正确的输入名称 "input"
        input_dict = {"input": processed_data}
        
        # 执行推理
        predictions = self.model.predict(input_dict)
        
        # 打印更多调试信息
        print(f"预测结果类型: {type(predictions)}")
        if isinstance(predictions, dict):
            print(f"预测结果键: {predictions.keys()}")
        
        return predictions

def main():
    # 示例用法
    # MODEL_PATH = "/Users/wayne/Documents/work/code/project/ffalcon/micro-hand-gesture/MicroHandGestureCollectorIWatch/MicroHandGestureCollectorIWatch Watch App/GestureModel_1.mlpackage"
    MODEL_PATH = "/Users/wayne/Documents/work/code/project/ffalcon/micro-hand-gesture/MicroHandGestureCollectorIWatch/python/GestureClassifier.mlpackage"
    
    # 创建推理器实例
    inferencer = MLPackageInference(MODEL_PATH)
    
    # 准备示例输入数据
    # sample_input = np.random.randn(10)  # 假设输入是10维向量
    sample_input = np.loadtxt(
        '/Users/wayne/Downloads/2025_01_03_11_18_10_王也_左手_单击[正]_轻_静坐/gesture_model_data_2.txt',
        skiprows=2,
        delimiter=','
	)[:, 7:].reshape(1, 6, 60)
    print(sample_input.shape)
    
    # 执行推理
    try:
        result = inferencer.predict(sample_input)
        print("推理结果:", result)
    except Exception as e:
        print(f"推理过程中出错: {str(e)}")

if __name__ == "__main__":
    main()