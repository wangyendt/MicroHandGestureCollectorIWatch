import torch
import torch.nn as nn
import numpy as np

class VanillaCNN(nn.Module):
    def __init__(self, num_classes):
        super(VanillaCNN, self).__init__()
        self.conv1 = nn.Conv1d(6, 12, kernel_size=3, padding=1, stride=1)
        self.bn1 = nn.BatchNorm1d(12)
        self.maxpool1 = nn.MaxPool1d(2, stride=2)
        self.conv2 = nn.Conv1d(12, 12, kernel_size=3, padding=1, stride=1)
        self.bn2 = nn.BatchNorm1d(12)
        self.maxpool2 = nn.MaxPool1d(4, stride=4)
        self.conv3 = nn.Conv1d(12, 6, kernel_size=3, padding=1, stride=1)
        self.bn3 = nn.BatchNorm1d(6)
        self.relu = nn.ReLU()
        self.fc = nn.Linear(6 * 7, num_classes)
        
    def forward(self, x):
        xx = self.maxpool1(self.relu(self.bn1(self.conv1(x))))
        xx = self.maxpool2(self.relu(self.bn2(self.conv2(xx))))
        xx = self.relu(self.bn3(self.conv3(xx)))
        xx = xx.view(xx.size(0), -1)  # flatten
        xx = self.fc(xx)  # logits
        return xx

class PyTorchInference:
    def __init__(self, model_path):
        """
        初始化PyTorch推理类
        Args:
            model_path: 模型权重文件的路径
        """
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.model = VanillaCNN(num_classes=9).to(self.device)
        self.model.load_state_dict(torch.load(model_path, map_location=self.device))
        self.model.eval()
        
        print("\n模型信息:")
        print(f"使用设备: {self.device}")
        print(f"模型结构:\n{self.model}\n")
        
    def preprocess(self, input_data):
        """
        预处理输入数据
        Args:
            input_data: numpy数组格式的输入数据
        Returns:
            处理后的PyTorch张量
        """
        # 确保数据类型正确并转换为PyTorch张量
        input_data = torch.FloatTensor(input_data).to(self.device)
        
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
        
        # 执行推理
        with torch.no_grad():
            logits = self.model(processed_data)
            probabilities = torch.softmax(logits, dim=1)
        
        # 转换为numpy数组
        probabilities = probabilities.cpu().numpy()
        
        # 打印预测结果
        print(f"预测结果形状: {probabilities.shape}")
        print(f"预测概率值:\n{probabilities}")
        print(f"预测logits值:\n{logits}")
        
        return probabilities

def main():
    # 模型路径
    MODEL_PATH = "/Users/wayne/Documents/work/code/project/ffalcon/micro-hand-gesture/MicroHandGestureCollectorIWatch/python/total_epoch=950_accuracy=0.989.pt"
    
    # 创建推理器实例
    inferencer = PyTorchInference(MODEL_PATH)
    
    # 准备示例输入数据
    sample_input = np.loadtxt(
        '/Users/wayne/Downloads/2025_01_03_11_18_10_王也_左手_单击[正]_轻_静坐/gesture_model_data_2.txt',
        skiprows=2,
        delimiter=',',
        encoding='utf-8'
    )[:, 7:].reshape(1, 6, 60)
    print(f"输入数据形状: {sample_input.shape}")
    
    # 执行推理
    try:
        result = inferencer.predict(sample_input)
        print("\n最终预测结果:")
        gesture_names = ["单击", "双击", "握拳", "左滑", "右滑", "鼓掌", "抖腕", "拍打", "日常"]
        predicted_class = np.argmax(result[0])
        confidence = result[0][predicted_class]
        print(f"预测手势: {gesture_names[predicted_class]}")
        print(f"置信度: {confidence:.4f}")
        print("\n所有类别的概率:")
        for i, (name, prob) in enumerate(zip(gesture_names, result[0])):
            print(f"{name}: {prob:.4f}")
    except Exception as e:
        print(f"推理过程中出错: {str(e)}")

if __name__ == "__main__":
    main()