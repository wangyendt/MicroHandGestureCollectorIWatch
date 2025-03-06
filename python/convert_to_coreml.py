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

class MBConv(nn.Module):
    def __init__(self, in_channels, out_channels, expand_ratio=4, stride=1, kernel_size=3, drop_rate=0.0):
 
        super(MBConv, self).__init__()
        self.expand_ratio = expand_ratio
        self.drop_rate = drop_rate
        hidden_dim = in_channels * expand_ratio

        # 1x1 Pointwise Convolution (Expansion)
        self.expand_conv = nn.Conv1d(in_channels, hidden_dim, kernel_size=1, bias=False) if expand_ratio != 1 else None
        self.expand_bn = nn.BatchNorm1d(hidden_dim) if expand_ratio != 1 else None
        self.expand_activation = nn.SiLU() if expand_ratio != 1 else None

        # Depthwise Convolution
        self.depthwise_conv = nn.Conv1d(hidden_dim, hidden_dim, kernel_size=kernel_size, stride=stride, padding=kernel_size // 2, groups=hidden_dim, bias=False)
        self.depthwise_bn = nn.BatchNorm1d(hidden_dim)
        self.depthwise_activation = nn.SiLU()

        # 1x1 Pointwise Convolution (Projection)
        self.project_conv = nn.Conv1d(hidden_dim, out_channels, kernel_size=1, bias=False)
        self.project_bn = nn.BatchNorm1d(out_channels)

        # Skip connection
        self.use_residual = stride == 1 and in_channels == out_channels
        self.dropout = nn.Dropout(drop_rate) if drop_rate > 0.0 else None

    def forward(self, x):
        identity = x

        # Expansion phase
        if self.expand_conv is not None:
            x = self.expand_conv(x)
            x = self.expand_bn(x)
            x = self.expand_activation(x)

        # Depthwise convolution
        x = self.depthwise_conv(x)
        x = self.depthwise_bn(x)
        x = self.depthwise_activation(x)

        # Projection phase
        x = self.project_conv(x)
        x = self.project_bn(x)

        # Residual connection
        if self.use_residual:
            if self.dropout is not None:
                x = self.dropout(x)
            x = x + identity

        return x
    

class SeparableConv(nn.Module):
    def __init__(self, in_channels, out_channels, kernel_size, stride=1, padding=0, dilation=1, bias=True):

        super(SeparableConv, self).__init__()
        # Depthwise Convolution
        self.depthwise = nn.Conv1d(
            in_channels,
            in_channels,
            kernel_size=kernel_size,
            stride=stride,
            padding=padding,
            dilation=dilation,
            groups=in_channels,  # Ensures each input channel is treated independently
            bias=bias
        )
        # Pointwise Convolution
        self.pointwise = nn.Conv1d(
            in_channels,
            out_channels,
            kernel_size=1,
            bias=bias
        )

    def forward(self, x):
        x = torch.relu(self.depthwise(x))
        x = torch.relu(self.pointwise(x))
        return x

class GestureModel(nn.Module):
    def __init__(self, num_classes):
        super(GestureModel, self).__init__()
        
        self.conv1 = MBConv(1, 16, 1, 1, 9)
        self.conv2 = MBConv(16, 24, 6, 2, 9)
        self.conv3 = SeparableConv(144, 24, 9)
        self.pool1 = nn.MaxPool1d(8)
        
        self.dense1 = nn.Linear(120, 80)
        self.dense2 = nn.Linear(80, 40)
        self.dense3 = nn.Linear(40, 20)
        self.dense4 = nn.Linear(20, num_classes)
        
        
    def forward(self, input):
        # input(6 dim): acc and gyro
        # x = self.preprocess(input)
        x = input
        B, C, F, _ = x.shape
        x = x.reshape(B * C, F, -1)
        
        x = self.conv1(x)
        x = self.conv2(x)
        _, _, L = x.shape
        
        x = x.reshape(B, -1, L)
        x = self.conv3(x)
        x = self.pool1(x)
        x = torch.flatten(x, start_dim=1)
        
        x = torch.relu(self.dense1(x))
        x = torch.relu(self.dense2(x))
        x = torch.relu(self.dense3(x))
        x = self.dense4(x)
        
        return x


# # 加载模型和权重
# model = VanillaCNN(num_classes=9)
# model.load_state_dict(torch.load('total_epoch=950_accuracy=0.989.pt', map_location='cpu'))


# # 创建示例输入
# example_input = torch.randn(1, 6, 60)

# # 转换为CoreML
# traced_model = torch.jit.trace(model, example_input)
# mlmodel = ct.convert(
#     traced_model,
#     inputs=[ct.TensorType(name="input", shape=example_input.shape)],
#     outputs=[ct.TensorType(name="output")],
#     minimum_deployment_target=ct.target.watchOS8
# )

# # 保存模型
# mlmodel.save("GestureClassifier.mlpackage")



model = GestureModel(num_classes=9)
model_path = 'valid_epoch=14_accuracy=0.960.pt'
model.load_state_dict(torch.load(model_path, map_location='cpu'))

# 导出CoreML模型
model.eval()
example_inputs = (torch.rand(1, 6, 1, 100),)

traced_model = torch.jit.trace(model, example_inputs[0])
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="input", shape=example_inputs[0].shape)],
    outputs=[ct.TensorType(name="output")],
    minimum_deployment_target=ct.target.watchOS8
)
# exported_program = torch.export.export(model, example_inputs)
mlmodel.author = "wy"
mlmodel.license = "rayneo"
mlmodel.short_description = "补充了权博的数据"
mlmodel.version = "0.0.9"  # 设置模型版本号

# import coremltools as ct
# mlmodel = ct.convert(exported_program)
mlmodel_path = "GestureModel_1.mlpackage"
mlmodel.save(mlmodel_path) 

print(f"模型导出完成，保存路径: {mlmodel_path}")
