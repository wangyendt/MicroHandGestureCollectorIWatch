import sys
sys.path.append('../pybind_libs/detrend_iir')
import h5py
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from scipy.signal import butter, lfilter
from butterworth_filter import ButterworthFilter
from pywayne.dsp import butter, butter_bandpass_filter
import os
import bisect
from itertools import cycle
from typing import Dict, List
import coremltools as ct
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.metrics import confusion_matrix, roc_curve, auc
from sklearn.preprocessing import label_binarize
from pywayne.tools import wayne_print


from matplotlib.font_manager import FontManager
fm = FontManager()
mat_fonts = set(f.name for f in fm.ttflist)
# print(mat_fonts)
plt.rcParams['font.sans-serif'] = ['Arial Unicode MS']



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

		self.version = "0.0.6"
		self.tag = "补充了几条数据"
		
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

class MHGDataSet(Dataset):
    def __init__(self, h5_path):
        self.h5_path = h5_path
        self.prefix_sum = [0]
        self.scenes = []
        self.init()
        self._all_data = None

    def init(self):
        with h5py.File(self.h5_path, 'r') as h5:
            for scene in sorted(h5.keys()):
                attr = h5[scene].attrs
#                 print(attr.keys())
                scene_len = len(h5[scene])
                self.prefix_sum.append(self.prefix_sum[-1] + scene_len)
                self.scenes.append(scene)
#                 wayne_print(f"{scene=}, {len(h5[scene])=}, {attr['date']=}, {attr['force_level']=}, {attr['handness']=}, {attr['note']=}, {attr['scene_kw']=}, {attr['scene_property']=}\n")
        print(self.prefix_sum)

    def __len__(self):
        return self.prefix_sum[-1]

    def __getitem__(self, idx):
        which_scene_idx, which_scene = self.get_scene_by_idx(idx)
        offset = str(idx - self.prefix_sum[which_scene_idx])
#         print(f'{offset=}')
        
        with h5py.File(self.h5_path, 'r') as h5:
            data = h5[which_scene][offset]  # 获取具体数据
            attr = dict(h5[which_scene].attrs)  # 转换属性为字典
#             print(which_scene)
#             print(22,h5[which_scene].attrs.keys())
            acc_rawdata = np.array(data['acc_rawdata'], dtype=float)
            gyro_rawdata = np.array(data['gyro_rawdata'], dtype=float)
            acc_filtered = np.array(data['acc_filtered'], dtype=float)
            gyro_filtered = np.array(data['gyro_filtered'], dtype=float)
#             x = np.c_[acc_rawdata, gyro_rawdata]
            x = torch.from_numpy(np.c_[acc_filtered, gyro_filtered])
            x = x.permute(1, 0)
            x = x[:, None, :]
            y = torch.from_numpy(y_lbl2onehot[data.attrs['gt']])
            return x.float(), y.float()
        
    def get_all_data(self):
        dtype = torch.float32
        x_all, y_all = [], []
        with h5py.File(self.h5_path, 'r') as h5:
            for scene in sorted(h5.keys()):
                for idx in h5[scene]:
                    kw = f'{scene}/{idx}'
                    x = torch.tensor(np.c_[
                        h5[kw]['acc_filtered'][()],
                        h5[kw]['gyro_filtered'][()]
                    ][:,None,:], dtype=dtype)
                    y = torch.tensor(y_lbl2onehot[h5[kw].attrs['gt']], 
                                   dtype=dtype)
                    x_all.append(x)
                    y_all.append(y)
                    del x, y

        # print(torch.stack(x_all).shape)
        x_all_tensor = torch.stack(x_all).permute(0, 3, 2, 1)
        y_all_tensor = torch.stack(y_all)
        # print(x_all_tensor.shape, y_all_tensor.shape)
        del x_all, y_all
        return x_all_tensor, y_all_tensor
        
    def get_scene_by_idx(self, idx):
        which_scene_idx = bisect.bisect_right(self.prefix_sum, idx) - 1
        which_scene = self.scenes[which_scene_idx]
        return which_scene_idx, which_scene
    
    def get_attr_by_idx(self, idx):
        which_scene_idx, which_scene = self.get_scene_by_idx(idx)
        offset = str(idx - self.prefix_sum[which_scene_idx])
        
        with h5py.File(self.h5_path, 'r') as h5:
            data = h5[which_scene][offset]  # 获取具体数据
            attr = dict(h5[which_scene].attrs)  # 转换属性为字典
            return attr
        
    def visualize_by_idx(self, idx):
        plt.close('all')
        x, y = self[idx]
        attr = self.get_attr_by_idx(idx)
        fig, ax = plt.subplots(2, 1, sharex='all')
        ax[0].plot(x.squeeze().T[:,:3])
        ax[0].legend(('x','y','z'))
        ax[1].plot(x.squeeze().T[:,3:])
        ax[1].legend(('x','y','z'))
        [a.grid(True) for a in ax]
        plt.suptitle('_'.join(attr.values()))
        plt.show()

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


def calculate_confusion_matrix(y_pred, y_true, class_mapping, dataset_name):
    # 确保输入是 numpy 数组
    y_pred = np.array(y_pred)
    y_true = np.array(y_true)
    
    # 获取预测值和真实值中的类别
    # classes = sorted(list(set(np.unique(y_pred)) | set(np.unique(y_true))))
    classes = list(range(len(class_mapping)))
    
    # 计算混淆矩阵
    n_classes = len(class_mapping)
    cm = confusion_matrix(y_true, y_pred, labels=range(n_classes))
    
    # 获取映射后的标签
    labels = [class_mapping[i] for i in classes]
    
    plt.close('all')
    
    # 创建图形
    fig = plt.figure(figsize=(10, 8))
    
    # 创建主热力图，但不显示上方标签
    ax = sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                     xticklabels=[], yticklabels=labels)
    
    # 创建顶部的第二个x轴
    ax2 = ax.twiny()
    
    # 设置上方x轴的刻度和标签
    ax2.set_xlim(ax.get_xlim())
    ax2.set_xticks(np.arange(len(labels)) + 0.5)
    ax2.set_xticklabels(labels, ha='left')
    
    # 设置标签位置
    ax2.set_xlabel('Predicted')
    ax2.xaxis.set_label_position('top')
    
    plt.ylabel('True')
    plt.title(f'Confusion Matrix of {dataset_name}')
    
    # 调整布局以防止标签被裁剪
    plt.tight_layout()
    # plt.show()
    
    return cm, classes, fig

def calculate_advanced_metrics(confusion_matrix: np.ndarray, 
                             y_true: np.ndarray = None,
                             y_pred: np.ndarray = None,
                             y_prob: np.ndarray = None) -> dict:
    """
    计算混淆矩阵的各种高级评估指标，并可选择性地生成ROC曲线。
    
    参数:
        confusion_matrix: numpy.ndarray, 形状为(n, n)的混淆矩阵
        y_true: 真实标签，形状为(N,)
        y_pred: 预测的类别，形状为(N,)
        y_prob: 预测的概率分布，形状为(N, n_classes)，用于ROC曲线
    """
    if not isinstance(confusion_matrix, np.ndarray):
        confusion_matrix = np.array(confusion_matrix)
    
    n_classes = confusion_matrix.shape[0]
    
    # 1. 基础指标计算
    tp = np.diag(confusion_matrix)
    fp = np.sum(confusion_matrix, axis=0) - tp
    fn = np.sum(confusion_matrix, axis=1) - tp
    tn = np.sum(confusion_matrix) - (tp + fp + fn)
    
    # 2. 计算基础指标
    precision = np.zeros(n_classes)
    recall = np.zeros(n_classes)
    specificity = np.zeros(n_classes)
    f1_score = np.zeros(n_classes)
    
    for i in range(n_classes):
        precision[i] = tp[i] / (tp[i] + fp[i]) if (tp[i] + fp[i]) > 0 else 0
        recall[i] = tp[i] / (tp[i] + fn[i]) if (tp[i] + fn[i]) > 0 else 0
        specificity[i] = tn[i] / (tn[i] + fp[i]) if (tn[i] + fp[i]) > 0 else 0
        f1_score[i] = 2 * (precision[i] * recall[i]) / (precision[i] + recall[i]) if (precision[i] + recall[i]) > 0 else 0
    
    # 3. 计算高级指标
    # Cohen's Kappa
    total = np.sum(confusion_matrix)
    observed_accuracy = np.sum(tp) / total
    expected_accuracy = sum(np.sum(confusion_matrix, axis=0) * np.sum(confusion_matrix, axis=1)) / (total * total)
    kappa = (observed_accuracy - expected_accuracy) / (1 - expected_accuracy)
    
    # Balanced Accuracy
    balanced_accuracy = np.mean(recall)
    
    # Matthews Correlation Coefficient (MCC)
    def multiclass_mcc(confusion_matrix):
        t_sum = confusion_matrix.sum()
        s = (confusion_matrix / t_sum).sum()
        r = np.sum(confusion_matrix, axis=1)
        c = np.sum(confusion_matrix, axis=0)
        t = np.trace(confusion_matrix)
        n = t_sum * t - np.sum(r * c)
        d = np.sqrt((t_sum**2 - np.sum(c * c)) * (t_sum**2 - np.sum(r * r)))
        return n / d if d != 0 else 0
    
    mcc = multiclass_mcc(confusion_matrix)
    
    # 4. 如果提供了预测概率，计算ROC曲线相关指标
    roc_data = None
    if y_true is not None and y_prob is not None:
        roc_data = calculate_multiclass_roc(y_true, y_prob, n_classes)
    
    return {
        'basic_metrics': {
            'precision': {
                'per_class': precision.tolist(),
                'macro_avg': float(np.mean(precision))
            },
            'recall': {
                'per_class': recall.tolist(),
                'macro_avg': float(np.mean(recall))
            },
            'f1_score': {
                'per_class': f1_score.tolist(),
                'macro_avg': float(np.mean(f1_score))
            },
            'accuracy': float(observed_accuracy)
        },
        'advanced_metrics': {
            'specificity': {
                'per_class': specificity.tolist(),
                'macro_avg': float(np.mean(specificity))
            },
            'balanced_accuracy': float(balanced_accuracy),
            'cohen_kappa': float(kappa),
            'matthews_correlation_coefficient': float(mcc)
        },
        'roc_data': roc_data
    }

def calculate_multiclass_roc(y_true: np.ndarray, y_prob: np.ndarray, n_classes: int) -> Dict:
    """
    计算多分类ROC曲线（one-vs-rest方式）
    
    参数:
        y_true: 真实标签，形状为(N,)
        y_prob: 预测概率，形状为(N, n_classes)
        n_classes: 类别数量
    """

    y_true = y_true.astype(int)
    
    # 获取实际出现的类别
    unique_classes = np.unique(y_true)
    
    # 将标签进行二值化处理，确保使用正确的类别范围
    y_true_bin = label_binarize(y_true, classes=range(n_classes))
    
    # 验证维度
    assert y_true_bin.shape[1] == y_prob.shape[1], f"标签形状不匹配: {y_true_bin.shape} vs {y_prob.shape}"


    # 将标签进行二值化处理
    # y_true_bin = label_binarize(y_true, classes=range(n_classes))
    
    # 计算每个类别的ROC曲线和AUC
    fpr = {}
    tpr = {}
    roc_auc = {}
    
    for i in range(n_classes):
        fpr[i], tpr[i], _ = roc_curve(y_true_bin[:, i], y_prob[:, i])
        roc_auc[i] = auc(fpr[i], tpr[i])
    
    # 计算微平均ROC曲线
    fpr["micro"], tpr["micro"], _ = roc_curve(y_true_bin.ravel(), y_prob.ravel())
    roc_auc["micro"] = auc(fpr["micro"], tpr["micro"])
    
    return {
        'fpr': fpr,
        'tpr': tpr,
        'roc_auc': roc_auc
    }

def plot_roc_curves(roc_data: Dict, n_classes: int, class_names: List[str] = None):
    """
    绘制ROC曲线
    
    参数:
        roc_data: ROC曲线数据
        n_classes: 类别数量
        class_names: 类别名称列表（可选）
    """
    plt.close('all')
    fig = plt.figure(figsize=(10, 8))
    
    # 设置颜色循环
    colors = cycle(['aqua', 'darkorange', 'cornflowerblue', 'green', 'red', 'purple', 'brown', 'pink', 'gray'])
    
    # 绘制每个类别的ROC曲线
    for i, color in zip(range(n_classes), colors):
        class_label = f'类别 {i}' if class_names is None else class_names[i]
        plt.plot(roc_data['fpr'][i], roc_data['tpr'][i], color=color, lw=2,
                label=f'ROC曲线 {class_label} (AUC = {roc_data["roc_auc"][i]:0.2f})')
    
    # 绘制微平均ROC曲线
    plt.plot(roc_data['fpr']['micro'], roc_data['tpr']['micro'],
            label=f'微平均ROC曲线 (AUC = {roc_data["roc_auc"]["micro"]:0.2f})',
            color='deeppink', linestyle=':', linewidth=4)
    
    # 绘制对角线
    plt.plot([0, 1], [0, 1], 'k--', lw=2)
    plt.xlim([0.0, 1.0])
    plt.ylim([0.0, 1.05])
    plt.xlabel('假阳性率')
    plt.ylabel('真阳性率')
    plt.title('多分类ROC曲线 (One-vs-Rest)')
    plt.legend(loc="lower right")
    plt.grid(True)
    # plt.show()
    
    return fig


def run_pytorch_model(model, best_model_path):
	# 加载测试数据集
	test_dataset = MHGDataSet('test.h5')
	test_x, test_y = test_dataset.get_all_data()

	wayne_print(f'use model: {best_model_path}', 'green')

	# 加载模型权重，指定map_location
	model.load_state_dict(torch.load(best_model_path, map_location=torch.device('cpu')))
	model.eval()

	criterion = nn.CrossEntropyLoss()
	
	# 在测试集上进行预测
	with torch.no_grad():
		test_x = test_x.to(device)
		test_out = model(test_x).cpu()
		test_loss = criterion(test_out, test_y)
		
		# 计算预测结果
		test_prob = torch.nn.functional.softmax(test_out, dim=1).numpy()
		test_pred = np.argmax(test_out.numpy(), axis=1)
		test_true = np.argmax(test_y.numpy(), axis=1)
		
		# 计算混淆矩阵
		cm, classes, cm_fig = calculate_confusion_matrix(test_pred, test_true, y_idx2lbl, 'test (PyTorch)')
		plt.show()
		
		# 计算评估指标
		metrics = calculate_advanced_metrics(
			cm,
			y_true=test_true,
			y_pred=test_pred,
			y_prob=test_prob
		)
		
		# 绘制ROC曲线
		if metrics['roc_data']:
			roc_fig = plot_roc_curves(metrics['roc_data'], cm.shape[1], y_idx2lbl)
		
		# 打印评估结果
		print(f"\n测试集损失: {test_loss.item():.4f}")
		print(f"\n基础指标:")
		print(f"准确率 (Accuracy): {metrics['basic_metrics']['accuracy']:.3f}")
		print(f"宏平均精确率: {metrics['basic_metrics']['precision']['macro_avg']:.3f}")
		print(f"宏平均召回率: {metrics['basic_metrics']['recall']['macro_avg']:.3f}")
		print(f"宏平均F1分数: {metrics['basic_metrics']['f1_score']['macro_avg']:.3f}")
		
		print("\n高级指标:")
		print(f"Cohen's Kappa: {metrics['advanced_metrics']['cohen_kappa']:.3f}")
		print(f"Matthews相关系数: {metrics['advanced_metrics']['matthews_correlation_coefficient']:.3f}")
		print(f"平衡准确率: {metrics['advanced_metrics']['balanced_accuracy']:.3f}")
		
		# 显示混淆矩阵和ROC曲线
		plt.show()

def run_mlpackage_model(best_model_path):
    inferencer = MLPackageInference(best_model_path)
    
    # 加载测试数据集
    test_dataset = MHGDataSet('test.h5')
    test_x, test_y = test_dataset.get_all_data()
    print(f"测试集形状: {test_x.shape}")
    
    # 存储所有预测结果
    all_predictions = []
    all_probabilities = []
    
    try:
        # 逐个样本进行预测
        for i in range(len(test_x)):
            # 准备单个样本
            single_sample = test_x[i:i+1]
            
            # 预测
            result = inferencer.predict(single_sample)
            
            # 提取预测概率和类别
            probabilities = result['output'].flatten()
            predicted_class = np.argmax(probabilities)
            
            all_predictions.append(predicted_class)
            all_probabilities.append(probabilities)
            
            # 打印进度
            if (i + 1) % 50 == 0:
                print(f"已处理 {i + 1}/{len(test_x)} 个样本")
        
        # 转换为numpy数组
        test_pred = np.array(all_predictions)
        test_prob = np.array(all_probabilities)
        test_true = np.argmax(test_y.numpy(), axis=1)
        
        # 计算混淆矩阵
        cm, classes, cm_fig = calculate_confusion_matrix(test_pred, test_true, y_idx2lbl, 'test (MLPackage)')
        plt.show()
        
        # 计算评估指标
        metrics = calculate_advanced_metrics(
            cm,
            y_true=test_true,
            y_pred=test_pred,
            y_prob=test_prob
        )
        
        # 绘制ROC曲线
        if metrics['roc_data']:
            roc_fig = plot_roc_curves(metrics['roc_data'], cm.shape[1], y_idx2lbl)
        
        # 打印评估结果
        print(f"\n基础指标:")
        print(f"准确率 (Accuracy): {metrics['basic_metrics']['accuracy']:.3f}")
        print(f"宏平均精确率: {metrics['basic_metrics']['precision']['macro_avg']:.3f}")
        print(f"宏平均召回率: {metrics['basic_metrics']['recall']['macro_avg']:.3f}")
        print(f"宏平均F1分数: {metrics['basic_metrics']['f1_score']['macro_avg']:.3f}")
        
        print("\n高级指标:")
        print(f"Cohen's Kappa: {metrics['advanced_metrics']['cohen_kappa']:.3f}")
        print(f"Matthews相关系数: {metrics['advanced_metrics']['matthews_correlation_coefficient']:.3f}")
        print(f"平衡准确率: {metrics['advanced_metrics']['balanced_accuracy']:.3f}")
        
        # 显示混淆矩阵和ROC曲线
        plt.show()
        
    except Exception as e:
        print(f"推理过程中出错: {str(e)}")

if __name__ == '__main__':
	device = 'cpu'
	# y_idx2lbl = ['单击', '双击', '握拳', '左滑', '右滑', '鼓掌', '抖腕', '拍打', '日常']
	y_idx2lbl = ['单击', '双击', '左摆', '右摆', '握拳', "摊掌", "转腕", "旋腕", "其它"]
	y_lbl2idx = {l: i for i, l in enumerate(y_idx2lbl)}
	y_lbl2onehot = {l: np.eye(len(y_idx2lbl))[i] for i, l in enumerate(y_idx2lbl)}
	wayne_print(y_lbl2idx, 'green')
	wayne_print(y_lbl2onehot, 'green')

	run_pytorch_model(
        GestureModel(len(y_idx2lbl)).to(device), 'valid_epoch=11_accuracy=0.963.pt'
    )
	# run_mlpackage_model('GestureModel_1.mlpackage')

