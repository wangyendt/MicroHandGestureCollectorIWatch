import torch
import torch.nn as nn
import coremltools as ct
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

# 加载模型和权重
model = VanillaCNN(num_classes=9)
model.load_state_dict(torch.load('total_epoch=950_accuracy=0.989.pt', map_location='cpu'))
model.eval()

# 创建示例输入
example_input = torch.randn(1, 6, 60)

# 转换为CoreML
traced_model = torch.jit.trace(model, example_input)
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="input", shape=example_input.shape)],
    outputs=[ct.TensorType(name="output")],
    minimum_deployment_target=ct.target.watchOS8
)

# 保存模型
mlmodel.save("GestureClassifier.mlpackage") 