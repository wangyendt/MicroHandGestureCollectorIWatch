import Foundation
import CoreML
import Accelerate

public class GestureRecognizer {
    private var gestureClassifier: GestureClassifier?
    private var imuBuffer: [(timestamp: TimeInterval, acc: SIMD3<Double>, gyro: SIMD3<Double>)] = []
    private let bufferCapacity = 100  // 保存1秒的数据
    private var saveGestureData = false
    private var currentFolderURL: URL?
    private var gestureCount = 0  // 添加计数器
    
    public init() {
        do {
            let config = MLModelConfiguration()
            gestureClassifier = try GestureClassifier(configuration: config)
        } catch {
            print("Error loading model: \(error)")
        }
    }
    
    public func addIMUData(timestamp: TimeInterval, acc: SIMD3<Double>, gyro: SIMD3<Double>) {
        imuBuffer.append((timestamp: timestamp, acc: acc, gyro: gyro))
        if imuBuffer.count > bufferCapacity {
            imuBuffer.removeFirst()
        }
    }
    
    public func recognizeGesture(atPeakTime peakTime: TimeInterval) -> (gesture: String, confidence: Double)? {
        // 找到峰值在缓冲区中的位置
        guard let peakIndex = imuBuffer.firstIndex(where: { $0.timestamp >= peakTime }) else {
            return nil
        }
        
        // 确保有足够的前后数据
        if peakIndex < 30 || imuBuffer.count - peakIndex < 30 {
            print("峰值位置不满足前后30帧的要求")
            return nil
        }
        
        // 提取前后30帧数据
        let startIndex = peakIndex - 30
        let endIndex = peakIndex + 29
        let data = Array(imuBuffer[startIndex...endIndex])
        
        // 确保正好60帧
        guard data.count == 60 else {
            print("数据帧数不正确: \(data.count)")
            return nil
        }
        
        // 分离加速度和陀螺仪数据
        var accData = [[Double]]()
        var gyroData = [[Double]]()
        
        for sample in data {
            accData.append([sample.acc.x, sample.acc.y, sample.acc.z])
            gyroData.append([sample.gyro.x, sample.gyro.y, sample.gyro.z])
        }
        
        // 对加速度数据进行带通滤波
        let accFiltered = butterBandpassFilter(
            data: accData,
            fs: 100.0,
            lowCut: 0.1,
            highCut: 40.0
        ).map { $0.map { $0 / 9.81 } }  // 转换为g
        
        // 组合处理后的数据用于模型输入
        var modelInputData = [Double]()
        for i in 0..<60 {
            modelInputData.append(contentsOf: accFiltered[i])
            modelInputData.append(contentsOf: gyroData[i])
        }
        
        // 进行预测
        let prediction = predict(processedData: modelInputData)
        
        // 保存数据（原始数据和处理后的数据）
        if prediction != nil {
            let rawData = data.map { ($0.acc, $0.gyro) }
            let processedData = zip(accFiltered, gyroData).map { (acc: $0, gyro: $1) }
            saveGestureData(rawData: rawData, processedData: processedData, prediction: prediction)
        }
        
        return prediction
    }
    
    private func predict(processedData: [Double]) -> (gesture: String, confidence: Double)? {
        guard let model = gestureClassifier else { return nil }
        
        // 创建模型输入
        guard let inputArray = try? MLMultiArray(shape: [1, 6, 60], dataType: .float32) else {
            print("Failed to create input array")
            return nil
        }
        
        // 填充数据
        for i in 0..<processedData.count {
            inputArray[i] = NSNumber(value: Float(processedData[i]))
        }
        
        // 进行预测
        do {
            let input = GestureClassifierInput(input: inputArray)
            let output = try model.prediction(input: input)
            let probabilities = output.output
            
            // 获取最高概率的类别
            var maxProb: Float = 0
            var predictedClass = 0
            
            for i in 0..<9 {
                let prob = probabilities[i].floatValue
                if prob > maxProb {
                    maxProb = prob
                    predictedClass = i
                }
            }
            
            // 获取预测结果
            let gestureNames = ["单击", "双击", "握拳", "左滑", "右滑", "鼓掌", "抖腕", "拍打", "日常"]
            let predictedGesture = gestureNames[predictedClass]
            
            return (gesture: predictedGesture, confidence: Double(maxProb))
        } catch {
            print("Prediction error: \(error)")
            return nil
        }
    }
    
    // 添加滤波器类型枚举
    private enum FilterType {
        case lowpass
        case highpass
        case bandpass
        case bandstop
    }
    
    // 添加 Butterworth 滤波器类
    private class ButterworthFilter {
        private let b = [0.63602426, 0.0, -1.27204851, 0.0, 0.63602426]
        private let a = [1.0, -0.84856511, -0.87090805, 0.31034215, 0.40923166]
        
        func filter(_ x: [Double]) -> [Double] {
            // 去除信号趋势
            let detrended = detrend(x)
            
            // 计算边界扩展
            let (edge, ext) = validatePad(x: detrended)
            
            // 计算初始状态
            let zi = lfilterZi()
            
            // 正向滤波
            let x0 = ext[0]
            var (y, _) = lfilter(ext, zi: zi.map { $0 * x0 })
            
            // 反向滤波
            let y0 = y[y.count - 1]
            y.reverse()
            (y, _) = lfilter(y, zi: zi.map { $0 * y0 })
            y.reverse()
            
            // 提取有效部分
            return Array(y[edge..<(y.count - edge)])
        }
        
        private func detrend(_ x: [Double]) -> [Double] {
            let n = x.count
            guard n > 1 else { return x }
            
            // 计算线性趋势
            let x_idx = Array(0..<n).map { Double($0) }
            let mean_x = x_idx.reduce(0.0, +) / Double(n)
            let mean_y = x.reduce(0.0, +) / Double(n)
            
            var slope = 0.0
            var numerator = 0.0
            var denominator = 0.0
            
            for i in 0..<n {
                let dx = x_idx[i] - mean_x
                let dy = x[i] - mean_y
                numerator += dx * dy
                denominator += dx * dx
            }
            
            if denominator != 0 {
                slope = numerator / denominator
            }
            
            // 移除趋势
            return x.enumerated().map { i, y in
                y - (slope * Double(i) + (mean_y - slope * mean_x))
            }
        }
        
        private func validatePad(x: [Double]) -> (edge: Int, ext: [Double]) {
            let ntaps = max(a.count, b.count)
            let edge = ntaps * 3
            
            // 使用奇对称扩展
            var ext = [Double](repeating: 0.0, count: x.count + 2 * edge)
            
            // 复制主信号
            for i in 0..<x.count {
                ext[i + edge] = x[i]
            }
            
            // 奇对称扩展边界
            for i in 0..<edge {
                ext[i] = 2 * x[0] - x[edge - i - 1]
                ext[ext.count - 1 - i] = 2 * x[x.count - 1] - x[x.count - 2 - i]
            }
            
            return (edge, ext)
        }
        
        private func lfilterZi() -> [Double] {
            let n = max(a.count, b.count) - 1
            var zi = [Double](repeating: 0.0, count: n)
            
            let sum_b = b.reduce(0.0, +)
            let sum_a = a.reduce(0.0, +)
            
            if abs(sum_a) > 1e-6 {
                let gain = sum_b / sum_a
                for i in 0..<zi.count {
                    zi[i] = gain
                }
            }
            
            return zi
        }
        
        private func lfilter(_ x: [Double], zi: [Double]) -> (y: [Double], zf: [Double]) {
            let n = x.count
            var y = [Double](repeating: 0.0, count: n)
            var z = zi
            
            // 使用直接II型结构实现滤波
            for i in 0..<n {
                y[i] = b[0] * x[i] + z[0]
                
                // 更新状态变量
                for j in 1..<a.count {
                    z[j-1] = b[j] * x[i] - a[j] * y[i] + (j < z.count ? z[j] : 0.0)
                }
            }
            
            return (y, z)
        }
    }
    
    private func butterBandpassFilter(data: [[Double]], fs: Double, lowCut: Double, highCut: Double) -> [[Double]] {
        let filter = ButterworthFilter()
        var filtered = Array(repeating: Array(repeating: 0.0, count: data[0].count), count: data.count)
        
        // 对每个通道进行滤波
        for ch in 0..<data[0].count {
            let channelData = data.map { $0[ch] }
            filtered.indices.forEach { i in
                filtered[i][ch] = filter.filter(channelData)[i]
            }
        }
        
        return filtered
    }
    
    public func updateSettings(saveGestureData: Bool) {
        self.saveGestureData = saveGestureData
    }
    
    public func setCurrentFolder(_ url: URL) {
        currentFolderURL = url
        gestureCount = 0  // 重置计数器
    }
    
    public func closeFiles() {
        gestureCount = 0  // 重置计数器
    }
    
    private func saveGestureData(rawData: [(acc: SIMD3<Double>, gyro: SIMD3<Double>)], 
                                processedData: [(acc: [Double], gyro: [Double])],
                                prediction: (gesture: String, confidence: Double)?) {
        guard saveGestureData,
              let folderURL = currentFolderURL,
              let prediction = prediction else { return }
        
        gestureCount += 1
        let fileName = "gesture_model_data_\(gestureCount).txt"
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        var fileContent = "# 预测结果：手势类别 = \(prediction.gesture), 置信度 = \(String(format: "%.3f", prediction.confidence))\n"
        fileContent += "# 数据格式：frame_idx,raw_acc_x,raw_acc_y,raw_acc_z,raw_gyro_x,raw_gyro_y,raw_gyro_z,filtered_acc_x,filtered_acc_y,filtered_acc_z,raw_gyro_x,raw_gyro_y,raw_gyro_z\n"
        
        // 组合原始数据和处理后的数据
        for i in 0..<60 {
            let raw = rawData[i]
            let processed = processedData[i]
            
            // 检查处理后的数据是否有效
            guard !processed.acc.contains(where: { $0.isNaN || $0.isInfinite }) else {
                print("警告：第 \(i) 帧的滤波后数据包含无效值")
                continue
            }
            
            fileContent += String(format: "%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                                i,
                                raw.acc.x, raw.acc.y, raw.acc.z,
                                raw.gyro.x, raw.gyro.y, raw.gyro.z,
                                processed.acc[0], processed.acc[1], processed.acc[2],
                                raw.gyro.x, raw.gyro.y, raw.gyro.z)
        }
        
        do {
            try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("成功保存手势数据到: \(fileURL.path)")
        } catch {
            print("保存手势数据失败: \(error)")
        }
    }
}