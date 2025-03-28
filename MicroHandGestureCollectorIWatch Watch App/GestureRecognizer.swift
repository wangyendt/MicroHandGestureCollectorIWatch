import Foundation
import CoreML
import Accelerate

public class GestureRecognizer {
    // 模型参数配置
    private struct ModelParams {
        let modelType: Any.Type
        let gestureNames: [String]
        let halfWindowSize: Int
        let inputShape: [NSNumber]
        let outputKey: String
        let reshapeData: ([Double], MLMultiArray) -> Void
    }
    
    private let modelConfigs: [String: ModelParams] = [
        "wayne": ModelParams(
            modelType: GestureClassifier.self,
            gestureNames: ["单击", "双击", "握拳", "左滑", "右滑", "鼓掌", "抖腕", "拍打", "日常"],
            halfWindowSize: 30,
            inputShape: [1, 6, 60],
            outputKey: "output",
            reshapeData: { processedData, inputArray in
                // wayne模型的数据排列方式
                for i in 0..<processedData.count {
                    inputArray[i] = NSNumber(value: Float(processedData[i]))
                }
            }
        ),
        "haili": ModelParams(
            modelType: GestureModel_1.self,
            gestureNames: ["单击", "双击", "左摆", "右摆", "握拳", "摊掌", "反掌", "转腕", "旋腕", "日常"],
            halfWindowSize: 50,
            inputShape: [1, 6, 4, 100],
            outputKey: "linear_3",
            reshapeData: { processedData, inputArray in
                // haili模型的数据排列方式
                for i in 0..<processedData.count {
                    inputArray[i] = NSNumber(value: Float(processedData[i]))
                }
            }
        )
    ]
    
    // 定义模型处理器类型
    private typealias ModelProcessor = (MLMultiArray) throws -> MLMultiArray
    
    // 模型处理器字典
    private let modelProcessors: [String: ModelProcessor] = [
        "wayne": { inputArray in
            let model = try GestureClassifier(configuration: MLModelConfiguration())
            let input = GestureClassifierInput(input: inputArray)
            let output = try model.prediction(input: input)
            return output.output
        },
        "haili": { inputArray in
            let model = try GestureModel_1(configuration: MLModelConfiguration())
            let input = GestureModel_1Input(input: inputArray)
            let output = try model.prediction(input: input)
            return output.output
        }
    ]
    
    private let whoseModel: String
    private var gestureClassifier: Any?
    private var currentModelParams: ModelParams
    
    private var imuBuffer: [(timestamp: TimeInterval, acc: SIMD3<Double>, gyro: SIMD3<Double>)] = []
    private var saveGestureData = false
    private var currentFolderURL: URL?
    private var gestureCount = 0
    
    // 将依赖于 halfWindowSize 的属性改为计算属性
    private var modelInputLength: Int {
        return 2 * currentModelParams.halfWindowSize
    }
    
    private var bufferCapacity: Int {
        return 2 * modelInputLength
    }
    
    // 在GestureRecognizer类中添加性能分析相关属性
    private var profilingEnabled = false
    private var processingTimes: [String: Double] = [:]
    private var recognitionCount = 0
    
    // 在类定义开始添加预加载模型实例
    private var wayneCachedModel: GestureClassifier?
    private var hailiCachedModel: GestureModel_1?
    
    // 添加推理队列
    private let inferenceQueue = DispatchQueue(label: "com.wayne.inferenceQueue", qos: .userInitiated)
    
    // 修改init方法，预加载模型
    public init(whoseModel: String = "haili") {
        self.whoseModel = whoseModel
        guard let params = modelConfigs[whoseModel] else {
            fatalError("不支持的模型类型: \(whoseModel)")
        }
        self.currentModelParams = params
        
        // 从 UserDefaults 读取设置
        self.saveGestureData = UserDefaults.standard.bool(forKey: "saveGestureData")
        print("GestureRecognizer: 初始化时读取 saveGestureData = \(self.saveGestureData)")
        
        // 预加载模型
        do {
            let config = MLModelConfiguration()
            // 设置计算单元优先级，尽可能使用GPU或ANE
            config.computeUnits = .all
            
            if whoseModel == "wayne" {
                wayneCachedModel = try GestureClassifier(configuration: config)
                // 预热模型
                let dummyInput = try MLMultiArray(shape: [1, 6, 60], dataType: .float32)
                let dummyInputObj = GestureClassifierInput(input: dummyInput)
                _ = try wayneCachedModel?.prediction(input: dummyInputObj)
                print("Wayne模型预加载完成")
            } else if whoseModel == "haili" {
                hailiCachedModel = try GestureModel_1(configuration: config)
                // 预热模型
                let dummyInput = try MLMultiArray(shape: [1, 6, 4, 100], dataType: .float32)
                let dummyInputObj = GestureModel_1Input(input: dummyInput)
                _ = try hailiCachedModel?.prediction(input: dummyInputObj)
                print("Haili模型预加载完成")
            }
        } catch {
            print("Error preloading model: \(error)")
        }
    }
    
    public func addIMUData(timestamp: TimeInterval, acc: SIMD3<Double>, gyro: SIMD3<Double>) {
        imuBuffer.append((timestamp: timestamp, acc: acc, gyro: gyro))
        if imuBuffer.count > bufferCapacity {
            imuBuffer.removeFirst()
        }
    }
    
    // 添加异步推理方法
    public func recognizeGestureAsync(atPeakTime peakTime: TimeInterval, completion: @escaping ((gesture: String, confidence: Double)?) -> Void) {
        let recognitionStartTime = CFAbsoluteTimeGetCurrent()
        
        // 找到峰值在缓冲区中的位置
        guard let peakIndex = imuBuffer.firstIndex(where: { $0.timestamp >= peakTime }) else {
            completion(nil)
            return
        }
        
        // 确保有足够的前后数据
        if peakIndex < currentModelParams.halfWindowSize || imuBuffer.count - peakIndex < currentModelParams.halfWindowSize {
            print("峰值位置不满足前后\(currentModelParams.halfWindowSize)帧的要求")
            completion(nil)
            return
        }
        
        // 提取前后数据
        let startIndex = peakIndex - currentModelParams.halfWindowSize
        let endIndex = peakIndex + (currentModelParams.halfWindowSize - 1)
        let data = Array(imuBuffer[startIndex...endIndex])
        
        // 确保正好所需帧数
        guard data.count == modelInputLength else {
            print("数据帧数不正确: \(data.count)")
            completion(nil)
            return
        }
        
        // 性能分析：数据提取阶段
        let dataExtractTime = (CFAbsoluteTimeGetCurrent() - recognitionStartTime) * 1000
        
        // 分离加速度和陀螺仪数据
        let dataProcessStartTime = CFAbsoluteTimeGetCurrent()
        var accData = [[Double]]()
        var gyroData = [[Double]]()
        
        for sample in data {
            accData.append([sample.acc.x, sample.acc.y, sample.acc.z])
            gyroData.append([sample.gyro.x, sample.gyro.y, sample.gyro.z])
        }
        
        let dataSplitTime = (CFAbsoluteTimeGetCurrent() - dataProcessStartTime) * 1000
        
        // 对加速度和陀螺仪数据进行滤波和格式化
        let filterAndFormatData = { () -> [Double] in
            let filterStartTime = CFAbsoluteTimeGetCurrent()
            
            // 对加速度数据进行带通滤波
            let accFiltered_low = self.butterBandpassFilter(
                data: accData,
                coefficientType: .low
            ).map { $0.map { $0 / 9.81 } }  // 转换为g

            let accFiltered_mid = self.butterBandpassFilter(
                data: accData,
                coefficientType: .mid
            ).map { $0.map { $0 / 9.81 } }  // 转换为g

            let accFiltered_high = self.butterBandpassFilter(
                data: accData,
                coefficientType: .high
            ).map { $0.map { $0 / 9.81 } }  // 转换为g
            
            // 对陀螺仪数据进行带通滤波
            let gyroFiltered_low = self.butterBandpassFilter(
                data: gyroData,
                coefficientType: .low
            )

            let gyroFiltered_mid = self.butterBandpassFilter(
                data: gyroData,
                coefficientType: .mid
            )

            let gyroFiltered_high = self.butterBandpassFilter(
                data: gyroData,
                coefficientType: .high
            )
            
            let filterTime = (CFAbsoluteTimeGetCurrent() - filterStartTime) * 1000
            
            if self.profilingEnabled {
                self.processingTimes["filtering"] = (self.processingTimes["filtering"] ?? 0) + filterTime
            }

            // 组合处理后的数据用于模型输入
            let dataFormatStartTime = CFAbsoluteTimeGetCurrent()
            var modelInputData = [Double]()
            
            // 构造模型输入数据
            for c in 0..<3 {
                for i in 0..<self.modelInputLength {
                    modelInputData.append(accData[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(accFiltered_low[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(accFiltered_mid[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(accFiltered_high[i][c])
                }
            }
            for c in 0..<3 {
                for i in 0..<self.modelInputLength {
                    modelInputData.append(gyroData[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(gyroFiltered_low[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(gyroFiltered_mid[i][c])
                }
                for i in 0..<self.modelInputLength {
                    modelInputData.append(gyroFiltered_high[i][c])
                }
            }
            
            let dataFormatTime = (CFAbsoluteTimeGetCurrent() - dataFormatStartTime) * 1000
            
            if self.profilingEnabled {
                self.processingTimes["data_format"] = (self.processingTimes["data_format"] ?? 0) + dataFormatTime
            }
            
            return modelInputData
        }
        
        // 先在主线程处理数据预处理，然后在后台线程执行模型推理
        let modelInputData = filterAndFormatData()
        
        // 在后台线程执行模型推理
        inferenceQueue.async {
            let modelStartTime = CFAbsoluteTimeGetCurrent()
            let prediction = self.predictOptimized(processedData: modelInputData)
            let modelInferenceTime = (CFAbsoluteTimeGetCurrent() - modelStartTime) * 1000
            
            // 保存数据（原始数据和处理后的数据）
            let saveStartTime = CFAbsoluteTimeGetCurrent()
            if prediction != nil {
                let rawData = data.map { ($0.acc, $0.gyro) }
                let processedData = zip(accData, gyroData).map { (acc: $0, gyro: $1) }
                self.saveGestureData(rawData: rawData, processedData: processedData, prediction: prediction)
            }
            let saveTime = (CFAbsoluteTimeGetCurrent() - saveStartTime) * 1000
            
            // 记录性能指标
            if self.profilingEnabled {
                DispatchQueue.main.async {
                    self.recognitionCount += 1
                    self.processingTimes["data_extract"] = (self.processingTimes["data_extract"] ?? 0) + dataExtractTime
                    self.processingTimes["data_split"] = (self.processingTimes["data_split"] ?? 0) + dataSplitTime
                    self.processingTimes["model_inference"] = (self.processingTimes["model_inference"] ?? 0) + modelInferenceTime
                    self.processingTimes["data_save"] = (self.processingTimes["data_save"] ?? 0) + saveTime
                    
                    // 计算总时间
                    let totalTime = (CFAbsoluteTimeGetCurrent() - recognitionStartTime) * 1000
                    self.processingTimes["total_recognition"] = (self.processingTimes["total_recognition"] ?? 0) + totalTime
                    
                    // 每10次识别打印一次性能报告
                    if self.recognitionCount % 10 == 0 {
                        self.printRecognitionPerformanceReport()
                    }
                }
            }
            
            // 返回结果到主线程
            DispatchQueue.main.async {
                completion(prediction)
            }
        }
    }
    
    // 添加优化的预测方法
    private func predictOptimized(processedData: [Double]) -> (gesture: String, confidence: Double)? {
        let predictStartTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 创建输入数组
            guard let inputArray = try? MLMultiArray(shape: currentModelParams.inputShape,
                                                   dataType: .float32) else {
                print("Failed to create input array")
                return nil
            }
            
            // 重排数据
            let reshapeStartTime = CFAbsoluteTimeGetCurrent()
            currentModelParams.reshapeData(processedData, inputArray)
            let reshapeTime = (CFAbsoluteTimeGetCurrent() - reshapeStartTime) * 1000
            
            // 进行预测 - 使用预加载的模型直接推理
            let inferenceStartTime = CFAbsoluteTimeGetCurrent()
            
            var output: MLMultiArray
            
            if whoseModel == "wayne" {
                guard let model = wayneCachedModel else {
                    print("Wayne model not preloaded")
                    return nil
                }
                let input = GestureClassifierInput(input: inputArray)
                let result = try model.prediction(input: input)
                output = result.output
            } else { // haili
                guard let model = hailiCachedModel else {
                    print("Haili model not preloaded")
                    return nil
                }
                let input = GestureModel_1Input(input: inputArray)
                let result = try model.prediction(input: input)
                output = result.output
            }
            
            let inferenceTime = (CFAbsoluteTimeGetCurrent() - inferenceStartTime) * 1000
            
            // 处理输出
            let postProcessStartTime = CFAbsoluteTimeGetCurrent()
            let result = processOutput(output, gestureNames: currentModelParams.gestureNames)
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStartTime) * 1000
            
            // 记录性能指标
            if profilingEnabled {
                processingTimes["data_reshape"] = (processingTimes["data_reshape"] ?? 0) + reshapeTime
                processingTimes["model_inference_only"] = (processingTimes["model_inference_only"] ?? 0) + inferenceTime
                processingTimes["post_process"] = (processingTimes["post_process"] ?? 0) + postProcessTime
                processingTimes["predict_total"] = (processingTimes["predict_total"] ?? 0) + (CFAbsoluteTimeGetCurrent() - predictStartTime) * 1000
            }
            
            return result
        } catch {
            print("Prediction error: \(error)")
            return nil
        }
    }
    
    // 保留旧的同步方法作为备份，同时更新它使用优化的预测方法
    public func recognizeGesture(atPeakTime peakTime: TimeInterval) -> (gesture: String, confidence: Double)? {
        let recognitionStartTime = CFAbsoluteTimeGetCurrent()
        
        // 找到峰值在缓冲区中的位置
        guard let peakIndex = imuBuffer.firstIndex(where: { $0.timestamp >= peakTime }) else {
            return nil
        }
        
        // 确保有足够的前后数据
        if peakIndex < currentModelParams.halfWindowSize || imuBuffer.count - peakIndex < currentModelParams.halfWindowSize {
            print("峰值位置不满足前后\(currentModelParams.halfWindowSize)帧的要求")
            return nil
        }
        
        // 提取前后数据
        let startIndex = peakIndex - currentModelParams.halfWindowSize
        let endIndex = peakIndex + (currentModelParams.halfWindowSize - 1)
        let data = Array(imuBuffer[startIndex...endIndex])
        
        // 确保正好所需帧数
        guard data.count == modelInputLength else {
            print("数据帧数不正确: \(data.count)")
            return nil
        }
        
        // 性能分析：数据提取阶段
        let dataExtractTime = (CFAbsoluteTimeGetCurrent() - recognitionStartTime) * 1000
        
        // 分离加速度和陀螺仪数据
        let dataProcessStartTime = CFAbsoluteTimeGetCurrent()
        var accData = [[Double]]()
        var gyroData = [[Double]]()
        
        for sample in data {
            accData.append([sample.acc.x, sample.acc.y, sample.acc.z])
            gyroData.append([sample.gyro.x, sample.gyro.y, sample.gyro.z])
        }
        
        let dataSplitTime = (CFAbsoluteTimeGetCurrent() - dataProcessStartTime) * 1000
        
        // 对加速度数据进行带通滤波
        let filterStartTime = CFAbsoluteTimeGetCurrent()
        let accFiltered_low = butterBandpassFilter(
            data: accData,
            coefficientType: .low
        ).map { $0.map { $0 / 9.81 } }  // 转换为g

        let accFiltered_mid = butterBandpassFilter(
            data: accData,
            coefficientType: .mid
        ).map { $0.map { $0 / 9.81 } }  // 转换为g

        let accFiltered_high = butterBandpassFilter(
            data: accData,
            coefficientType: .high
        ).map { $0.map { $0 / 9.81 } }  // 转换为g
        
        
        // 对陀螺仪数据进行带通滤波
        let gyroFiltered_low = butterBandpassFilter(
            data: gyroData,
            coefficientType: .low  // 使用中频带通滤波器处理陀螺仪数据
        )

        let gyroFiltered_mid = butterBandpassFilter(
            data: gyroData,
            coefficientType: .mid
        )

        let gyroFiltered_high = butterBandpassFilter(
            data: gyroData,
            coefficientType: .high
        )
        
        let filterTime = (CFAbsoluteTimeGetCurrent() - filterStartTime) * 1000

        // 组合处理后的数据用于模型输入
        let dataFormatStartTime = CFAbsoluteTimeGetCurrent()
        var modelInputData = [Double]()
        for c in 0..<3 {
            for i in 0..<modelInputLength {
                modelInputData.append(accData[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(accFiltered_low[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(accFiltered_mid[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(accFiltered_high[i][c])
            }
        }
        for c in 0..<3 {
            for i in 0..<modelInputLength {
                modelInputData.append(gyroData[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(gyroFiltered_low[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(gyroFiltered_mid[i][c])
            }
            for i in 0..<modelInputLength {
                modelInputData.append(gyroFiltered_high[i][c])
            }
        }
        
        let dataFormatTime = (CFAbsoluteTimeGetCurrent() - dataFormatStartTime) * 1000
        
        // 进行预测 - 使用优化版本
        let modelStartTime = CFAbsoluteTimeGetCurrent()
        let prediction = predictOptimized(processedData: modelInputData)
        let modelInferenceTime = (CFAbsoluteTimeGetCurrent() - modelStartTime) * 1000
        
        // 保存数据（原始数据和处理后的数据）
        let saveStartTime = CFAbsoluteTimeGetCurrent()
        if prediction != nil {
            let rawData = data.map { ($0.acc, $0.gyro) }
            let processedData = zip(accData, gyroData).map { (acc: $0, gyro: $1) }
            saveGestureData(rawData: rawData, processedData: processedData, prediction: prediction)
        }
        let saveTime = (CFAbsoluteTimeGetCurrent() - saveStartTime) * 1000
        
        // 记录性能指标
        if profilingEnabled {
            recognitionCount += 1
            processingTimes["data_extract"] = (processingTimes["data_extract"] ?? 0) + dataExtractTime
            processingTimes["data_split"] = (processingTimes["data_split"] ?? 0) + dataSplitTime
            processingTimes["filtering"] = (processingTimes["filtering"] ?? 0) + filterTime
            processingTimes["data_format"] = (processingTimes["data_format"] ?? 0) + dataFormatTime
            processingTimes["model_inference"] = (processingTimes["model_inference"] ?? 0) + modelInferenceTime
            processingTimes["data_save"] = (processingTimes["data_save"] ?? 0) + saveTime
            
            // 计算总时间
            let totalTime = (CFAbsoluteTimeGetCurrent() - recognitionStartTime) * 1000
            processingTimes["total_recognition"] = (processingTimes["total_recognition"] ?? 0) + totalTime
            
            // 每10次识别打印一次性能报告
            if recognitionCount % 10 == 0 {
                printRecognitionPerformanceReport()
            }
        }
        
        return prediction
    }
    
    // 添加处理输出的辅助函数
    private func processOutput(_ output: MLMultiArray, gestureNames: [String]) -> (gesture: String, confidence: Double) {
        var logits = [Float]()
        for i in 0..<gestureNames.count {
            logits.append(output[i].floatValue)
        }
        
        let probabilities = softmax(logits)
        
        // 打印完整的概率向量和原始logits
        // print("原始 logits 值:")
        // for i in 0..<gestureNames.count {
        //     print("类别 \(i) (\(gestureNames[i])): \(logits[i])")
        // }
        
        // print("\n完整预测概率向量:")
        // for i in 0..<gestureNames.count {
        //     print("类别 \(i) (\(gestureNames[i])): \(probabilities[i])")
        // }
        
        // 获取最高概率的类别
        var maxProb: Float = 0
        var predictedClass = 0
        
        for i in 0..<gestureNames.count {
            let prob = probabilities[i]
            if prob > maxProb {
                maxProb = prob
                predictedClass = i
            }
        }
        
        let predictedGesture = gestureNames[predictedClass]
        print("预测结果: \(predictedGesture) (类别 \(predictedClass)), 置信度: \(maxProb)")
        
        return (gesture: predictedGesture, confidence: Double(maxProb))
    }
    
    // 添加滤波器类型枚举
    private enum FilterType {
        case lowpass
        case highpass
        case bandpass
        case bandstop
    }
    
    private enum FilterCoefficients {
        case standard  // 标准带通滤波器
        case low       // 低通滤波器
        case mid       // 中频带通滤波器
        case high      // 高通滤波器
        
        var coefficients: (b: [Double], a: [Double]) {
            switch self {
            case .standard:
                return ([0.63602426, 0.0, -1.27204851, 0.0, 0.63602426],
                        [1.0, -0.84856511, -0.87090805, 0.31034215, 0.40923166])
            case .low:
                return ([0.04366836, 0.0, -0.08733672, 0.0, 0.04366836],
                        [1.0, -3.31469991, 4.1362177, -2.32424114, 0.50276922])
            case .mid:
                return ([0.27472685, 0.0, -0.5494537, 0.0, 0.27472685],
                        [1.0, -0.87902961, 0.29755739, -0.17748527, 0.17253125])
            case .high:
                return ([0.17508764, -0.35017529, 0.17508764],
                        [1.0, 0.51930341, 0.21965398])
            }
        }
    }
    
    private func butterBandpassFilter(
        data: [[Double]], 
        coefficientType: FilterCoefficients = .standard
    ) -> [[Double]] {
        let filterStartTime = CFAbsoluteTimeGetCurrent()
        
        // 获取选定的滤波器系数
        let (b, a) = coefficientType.coefficients
        
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
        
        if profilingEnabled && currentModelParams.halfWindowSize > 0 {
            let filterTime = (CFAbsoluteTimeGetCurrent() - filterStartTime) * 1000
            let channelCount = data[0].count
            processingTimes["single_filter_\(coefficientType)"] = (processingTimes["single_filter_\(coefficientType)"] ?? 0) + filterTime / Double(channelCount)
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
        print("GestureRecognizer: Updating saveGestureData to \(saveGestureData)")  // 添加日志
        self.saveGestureData = saveGestureData
    }
    
    // 添加获取模型元数据的方法
    public func getModelMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        
        if whoseModel == "wayne", let model = gestureClassifier as? GestureClassifier {
            metadata["model_name"] = "GestureClassifier"
            // 尝试直接从模型中读取元数据
            let modelDescription = model.model.modelDescription
            
            // 使用正确的MLModelMetadataKey常量而不是字符串
            if let author = modelDescription.metadata[.author] as? String {
                metadata["model_author"] = author
            } else {
                metadata["model_author"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let version = modelDescription.metadata[.versionString] as? String {
                metadata["model_version"] = version
            } else {
                metadata["model_version"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let license = modelDescription.metadata[.license] as? String {
                metadata["model_license"] = license
            } else {
                metadata["model_license"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let description = modelDescription.metadata[.description] as? String {
                metadata["model_description"] = description
            } else {
                metadata["model_description"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            // 尝试读取用户自定义元数据 (creatorDefinedKey)
            if let userDefined = modelDescription.metadata[.creatorDefinedKey] as? [String: Any] {
                if let userAuthor = userDefined["author"] as? String {
                    metadata["model_author"] = userAuthor
                }
                if let userVersion = userDefined["version"] as? String {
                    metadata["model_version"] = userVersion
                }
                if let userLicense = userDefined["license"] as? String {
                    metadata["model_license"] = userLicense
                }
                if let userDescription = userDefined["description"] as? String {
                    metadata["model_description"] = userDescription
                }
            }
            
            // 打印完整元数据用于调试
            print("完整模型元数据：\(modelDescription.metadata)")
            
        } else if whoseModel == "haili", let model = gestureClassifier as? GestureModel_1 {
            metadata["model_name"] = "GestureModel_1"
            // 尝试直接从模型中读取元数据
            let modelDescription = model.model.modelDescription
            
            // 使用正确的MLModelMetadataKey常量而不是字符串
            if let author = modelDescription.metadata[.author] as? String {
                metadata["model_author"] = author
            } else {
                metadata["model_author"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let version = modelDescription.metadata[.versionString] as? String {
                metadata["model_version"] = version
            } else {
                metadata["model_version"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let license = modelDescription.metadata[.license] as? String {
                metadata["model_license"] = license
            } else {
                metadata["model_license"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            if let description = modelDescription.metadata[.description] as? String {
                metadata["model_description"] = description
            } else {
                metadata["model_description"] = "N/A" // 如果没有找到元数据，使用N/A
            }
            
            // 尝试读取用户自定义元数据 (creatorDefinedKey)
            if let userDefined = modelDescription.metadata[.creatorDefinedKey] as? [String: Any] {
                if let userAuthor = userDefined["author"] as? String {
                    metadata["model_author"] = userAuthor
                }
                if let userVersion = userDefined["version"] as? String {
                    metadata["model_version"] = userVersion
                }
                if let userLicense = userDefined["license"] as? String {
                    metadata["model_license"] = userLicense
                }
                if let userDescription = userDefined["description"] as? String {
                    metadata["model_description"] = userDescription
                }
            }
            
            // 打印完整元数据用于调试
            print("完整模型元数据：\(modelDescription.metadata)")
            
        } else {
            metadata["model_name"] = whoseModel
            metadata["model_author"] = "N/A"
            metadata["model_version"] = "N/A"
            metadata["model_license"] = "N/A"
            metadata["model_description"] = "N/A"
        }
        
        return metadata
    }
    
    public func setCurrentFolder(_ url: URL) {
        print("GestureRecognizer: Setting current folder to: \(url.path)")  // 添加日志
        currentFolderURL = url
        gestureCount = 0  // 重置计数器
    }
    
    public func closeFiles() {
        print("GestureRecognizer: Closing files")  // 添加日志
        gestureCount = 0  // 重置计数器
        currentFolderURL = nil  // 清除文件夹 URL
    }
    
    private func saveGestureData(rawData: [(acc: SIMD3<Double>, gyro: SIMD3<Double>)], 
                                processedData: [(acc: [Double], gyro: [Double])],
                                prediction: (gesture: String, confidence: Double)?) {
        // 添加调试日志
        print("Attempting to save gesture data. saveGestureData=\(saveGestureData), folderURL=\(String(describing: currentFolderURL))")
        
        guard saveGestureData,
              let folderURL = currentFolderURL,
              let prediction = prediction else {
            print("Failed to save gesture data: saveGestureData=\(saveGestureData), folderURL exists=\(currentFolderURL != nil)")
            return
        }
        
        gestureCount += 1
        let fileName = "gesture_model_data_\(gestureCount).txt"
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        var fileContent = "# 预测结果：手势类别 = \(prediction.gesture), 置信度 = \(String(format: "%.3f", prediction.confidence))\n"
        fileContent += "# 数据格式：frame_idx,raw_acc_x,raw_acc_y,raw_acc_z,raw_gyro_x,raw_gyro_y,raw_gyro_z,filtered_acc_x,filtered_acc_y,filtered_acc_z,raw_gyro_x,raw_gyro_y,raw_gyro_z\n"
        
        // 组合原始数据和处理后的数据
        for i in 0..<modelInputLength {
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
    
    // 添加 softmax 函数
    private func softmax(_ x: [Float]) -> [Float] {
        // 找到最大值用于数值稳定性
        let max = x.max() ?? 0
        
        // 计算 exp 并求和
        let exps = x.map { exp($0 - max) }
        let sum = exps.reduce(0, +)
        
        // 计算 softmax
        return exps.map { $0 / sum }
    }
    
    // 添加性能报告打印方法
    private func printRecognitionPerformanceReport() {
        guard profilingEnabled && recognitionCount > 0 else { return }
        
        print("\n========== 手势识别性能分析报告 ==========")
        print("总识别次数: \(recognitionCount)")
        
        for (operation, totalTime) in processingTimes.sorted(by: { $0.key < $1.key }) {
            let avgTime = totalTime / Double(recognitionCount)
            print("\(operation): 总计 \(String(format: "%.3f", totalTime)) ms, 平均 \(String(format: "%.3f", avgTime)) ms")
        }
        
        // 计算各阶段占比
        if let totalTime = processingTimes["total_recognition"] {
            print("\n各阶段耗时占比:")
            for (operation, time) in processingTimes.sorted(by: { $0.key < $1.key }) {
                if operation != "total_recognition" {
                    let percentage = time / totalTime * 100
                    print("\(operation): \(String(format: "%.2f", percentage))%")
                }
            }
        }
        
        print("==========================================\n")
    }
}
