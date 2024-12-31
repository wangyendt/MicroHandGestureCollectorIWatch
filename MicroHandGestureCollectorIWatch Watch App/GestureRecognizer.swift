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
    
    private func butterBandpassFilter(data: [[Double]], fs: Double, lowCut: Double, highCut: Double) -> [[Double]] {
        // 使用预定义的滤波器系数
        let b = [0.63602426, 0.0, -1.27204851, 0.0, 0.63602426]
        let a = [1.0, -0.84856511, -0.87090805, 0.31034215, 0.40923166]
        
        // 创建ButterworthFilter实例
        guard let filter = ButterworthFilterBridge(b: b as NSArray as! [NSNumber], a: a as NSArray as! [NSNumber]) else {
            print("Error: Failed to create ButterworthFilterBridge")
            return data // 如果创建失败，返回原始数据
        }
        
        // 对每个通道进行滤波
        var filtered = Array(repeating: Array(repeating: 0.0, count: data[0].count), count: data.count)
        
        for ch in 0..<data[0].count {
            let channelData = data.map { $0[ch] }
            // 将Double数组转换为NSNumber数组
            let channelDataNS = channelData.map { NSNumber(value: $0) }
            // 调用C++实现的滤波器
            if let filteredChannel = filter.filterData(channelDataNS) {
                filtered.indices.forEach { i in
                    filtered[i][ch] = filteredChannel[i].doubleValue
                }
            } else {
                // 如果滤波失败，使用原始数据
                filtered.indices.forEach { i in
                    filtered[i][ch] = data[i][ch]
                }
            }
        }
        
        return filtered
    }
    
    private func butterCoefficients(order: Int, lowW: Double, highW: Double) -> (b: [Double], a: [Double]) {
        // 带通滤波器的系数计算
        let wc = [lowW, highW]
        
        // 计算模拟滤波器的极点
        var poles: [Complex] = []
        for k in 0..<order {
            let theta = Double.pi * (2.0 * Double(k) + 1.0) / (2.0 * Double(order))
            let real = -sin(theta)
            let imag = cos(theta)
            poles.append(Complex(real: real, imag: imag))
        }
        
        // 双线性变换
        let fs = 2.0
        var warped: [Double] = []
        for w in wc {
            let warpedValue = 2.0 * fs * tan(.pi * w / fs)
            warped.append(warpedValue)
        }
        
        // 将模拟极点转换为数字极点
        var digitalPoles: [Complex] = []
        let c = 2.0 * fs
        for p in poles {
            let sReal = p.real * warped[1]
            let sImag = p.imag * warped[1]
            let denominator = c * c
            let real = (c + sReal) / denominator
            let imag = sImag / denominator
            digitalPoles.append(Complex(real: real, imag: imag))
        }
        
        // 计算滤波器系数
        var b = [Double](repeating: 0.0, count: order + 1)
        var a = [Double](repeating: 0.0, count: order + 1)
        
        // 将 Double 转换为 Float 进行计算
        let realPoles = digitalPoles.map { Float($0.real) }
        var coeffsFloat = [Float](repeating: 1.0, count: order + 1)
        
        // 使用正确的类型调用 vDSP_vpoly
        realPoles.withUnsafeBufferPointer { polesPtr in
            coeffsFloat.withUnsafeMutableBufferPointer { coeffsPtr in
                var tempCoeffs = [Float](repeating: 0.0, count: order + 1)
                vDSP_vrvrs(coeffsPtr.baseAddress!, 1, vDSP_Length(order + 1))
                vDSP_conv(polesPtr.baseAddress!, 1,
                         coeffsPtr.baseAddress!, 1,
                         &tempCoeffs, 1,
                         vDSP_Length(order + 1),
                         vDSP_Length(order + 1))
                for i in 0...order {
                    coeffsPtr[i] = tempCoeffs[i]
                }
            }
        }
        
        // 转回 Double
        let coeffs = coeffsFloat.map { Double($0) }
        
        // 归一化系数
        let gain = coeffs[0]
        b[0] = 1.0
        for i in 0...order {
            a[i] = coeffs[i] / gain
        }
        
        return (b, a)
    }
    
    private func filtfilt(x: [Double], b: [Double], a: [Double]) -> [Double] {
        // 边界处理
        let nfilt = max(b.count, a.count)
        let nfact = 3 * (nfilt - 1)
        let n = x.count
        
        // 填充边界
        var xPadded = [Double](repeating: 0.0, count: n + 2 * nfact)
        xPadded[nfact..<(n + nfact)] = x[0..<n]
        
        // 反射边界
        for i in 0..<nfact {
            xPadded[nfact - 1 - i] = 2 * xPadded[nfact] - xPadded[nfact + 1 + i]
            xPadded[n + nfact + i] = 2 * xPadded[n + nfact - 1] - xPadded[n + nfact - 2 - i]
        }
        
        // 正向滤波
        var y = forwardFilter(x: xPadded, b: b, a: a)
        
        // 反向滤波
        y.reverse()
        y = forwardFilter(x: y, b: b, a: a)
        y.reverse()
        
        // 返回有效部分
        return Array(y[nfact..<(n + nfact)])
    }
    
    private func forwardFilter(x: [Double], b: [Double], a: [Double]) -> [Double] {
        let n = x.count
        var y = [Double](repeating: 0.0, count: n)
        
        // 转换为 Float
        let xFloat = x.map { Float($0) }
        let bFloat = b.map { Float($0) }
        let aFloat = a.map { Float($0) }
        var yFloat = [Float](repeating: 0.0, count: n)
        
        // 使用 vDSP 进行滤波
        xFloat.withUnsafeBufferPointer { xPtr in
            bFloat.withUnsafeBufferPointer { bPtr in
                aFloat.withUnsafeBufferPointer { aPtr in
                    yFloat.withUnsafeMutableBufferPointer { yPtr in
                        var tempBuffer = [Float](repeating: 0.0, count: n + b.count)
                        
                        // 计算分子部分
                        vDSP_conv(xPtr.baseAddress!, 1,
                                bPtr.baseAddress!, 1,
                                &tempBuffer, 1,
                                vDSP_Length(n),
                                vDSP_Length(b.count))
                        
                        // 复制到输出
                        for i in 0..<n {
                            yPtr[i] = tempBuffer[i]
                        }
                        
                        // 计算分母部分（递归）
                        if a.count > 1 {
                            for i in 1..<n {
                                for j in 1..<min(i + 1, a.count) {
                                    yPtr[i] -= aPtr[j] * yPtr[i - j]
                                }
                                yPtr[i] /= aPtr[0]
                            }
                        }
                    }
                }
            }
        }
        
        // 转回 Double
        return yFloat.map { Double($0) }
    }
    
    // 复数结构体
    private struct Complex {
        var real: Double
        var imag: Double
        
        static func *(lhs: Complex, rhs: Double) -> Complex {
            return Complex(real: lhs.real * rhs, imag: lhs.imag * rhs)
        }
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