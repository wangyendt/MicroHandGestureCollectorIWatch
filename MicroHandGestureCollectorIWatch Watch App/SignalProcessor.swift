import Foundation
import Accelerate
import CoreMotion

class SignalProcessor {
    // 常量定义，与 Python 版本保持一致
    private let WINDOW_SIZE = 1000  // 10秒数据，100Hz
    private let PEAK_DELTA = 0.3  // peak detection的阈值
    private let SAMPLE_TIME = 0.01  // 采样时间(100Hz)
    
    // Peak detection状态
    private var lookformax = true
    private var mn: Double = .infinity
    private var mx: Double = -.infinity
    private var mnTime: TimeInterval = 0
    private var mxTime: TimeInterval = 0
    
    // 存储最近的峰值
    private var peaks: [(timestamp: TimeInterval, value: Double)] = []
    private var valleys: [(timestamp: TimeInterval, value: Double)] = []
    
    // OneEuro 滤波器
    private var filter: OneEuroFilter
    
    // 添加单调栈相关的属性
    private let peak_window = 1.0  // 300ms窗口
    private var candidate_peaks: [(timestamp: TimeInterval, value: Double)] = []
    private var monotonic_stack: [(timestamp: TimeInterval, value: Double)] = []
    private var last_selected_time: TimeInterval = -.infinity
    private var selected_peaks: [(timestamp: TimeInterval, value: Double)] = []
    
    // 添加代理协议来处理峰值检测事件
    weak var delegate: SignalProcessorDelegate?
    
    // 添加 VQF 相关属性
    private let vqf: VQFBridge
    private var lastQuaternion: [Double] = [1, 0, 0, 0] // w, x, y, z
    private var printQuatCounter = 0 // 用于控制打印频率
    
    init() {
        // 初始化 VQF，采样率 100Hz (0.01s)
        vqf = VQFBridge(gyrTs: 0.01, accTs: 0.01)
        
        filter = OneEuroFilter(
            te: SAMPLE_TIME,
            mincutoff: 10.0,
            beta: 0.001,
            dcutoff: 1.0
        )
    }
    
    // 计算信号范数
    func calculateNorm(x: Double, y: Double, z: Double) -> Double {
        return sqrt(x * x + y * y + z * z)
    }
    
    // 在线峰值检测，与 Python 版本保持一致
    func detectPeaks(timestamp: TimeInterval, value: Double) -> (peak: Double?, valley: Double?, isPeak: Bool, isValley: Bool) {
        var peak: Double? = nil
        var valley: Double? = nil
        var isPeak = false
        var isValley = false
        
        if lookformax {
            if value > mx {
                mx = value
                mxTime = timestamp
            } else if (mx - value) > PEAK_DELTA {
                peak = mx
                mn = value
                lookformax = false
                isPeak = true
            } else if value < mx && (mx - value) > PEAK_DELTA * 0.5 {
                peak = mx
                mn = value
                lookformax = false
                isPeak = true
            }
        } else {
            if value < mn {
                mn = value
                mnTime = timestamp
            } else if (value - mn) > PEAK_DELTA {
                valley = mn
                mx = value
                lookformax = true
                isValley = true
            } else if value > mn && (value - mn) > PEAK_DELTA * 0.5 {
                valley = mn
                mx = value
                lookformax = true
                isValley = true
            }
        }
        
        return (peak, valley, isPeak, isValley)
    }
    
    // 处理新的数据点
    func processNewPoint(timestamp: TimeInterval, accNorm: Double, acc: (x: Double, y: Double, z: Double)? = nil, gyro: (x: Double, y: Double, z: Double)? = nil) {
        // 如果提供了原始的加速度和陀螺仪数据，更新姿态解算
        if let acc = acc, let gyro = gyro {
            // 创建数组并转换为指针
            let accData: [Double] = [acc.x, acc.y, acc.z]
            let gyroData: [Double] = [gyro.x, gyro.y, gyro.z]
            
            // 使用 withUnsafePointer 安全地传递数组指针
            accData.withUnsafeBufferPointer { accPtr in
                gyroData.withUnsafeBufferPointer { gyroPtr in
                    // 更新 VQF
                    vqf.updateGyr(SAMPLE_TIME, gyr: UnsafeMutablePointer(mutating: gyroPtr.baseAddress!))
                    vqf.updateAcc(SAMPLE_TIME, acc: UnsafeMutablePointer(mutating: accPtr.baseAddress!))
                }
            }
            
            // 获取姿态四元数
            var quaternion = [Double](repeating: 0, count: 4)
            quaternion.withUnsafeMutableBufferPointer { quatPtr in
                vqf.getQuat6D(quatPtr.baseAddress!)
            }
            lastQuaternion = quaternion
            
            // 每100帧打印一次四元数
            printQuatCounter += 1
            if printQuatCounter >= 100 {
                print("Current quaternion [w,x,y,z]: [\(String(format: "%.4f", lastQuaternion[0])), \(String(format: "%.4f", lastQuaternion[1])), \(String(format: "%.4f", lastQuaternion[2])), \(String(format: "%.4f", lastQuaternion[3]))]")
                printQuatCounter = 0
            }
        }
        
        // 应用 OneEuro 滤波
        let filteredValue = filter.apply(val: accNorm, te: SAMPLE_TIME)
        
        // 检测峰值
        let (peak, valley, isPeak, isValley) = detectPeaks(timestamp: timestamp, value: filteredValue)
        
        if isPeak, let peakValue = peak {
            print("检测到Peak: \(String(format: "%.2f", peakValue)) @ \(String(format: "%.2f", timestamp))s")
            peaks.append((timestamp: timestamp, value: peakValue))
            if peaks.count > 100 {
                peaks.removeFirst()
            }
            
            // 添加到候选peaks
            if peakValue > 0.3 {
                candidate_peaks.append((timestamp: timestamp, value: peakValue))
                
                // 维护单调栈
                while !monotonic_stack.isEmpty && monotonic_stack.last!.value <= peakValue {
                    monotonic_stack.removeLast()
                }
                monotonic_stack.append((timestamp: timestamp, value: peakValue))
            }
        }
        
        // 检查候选peaks
        checkCandidatePeaks(currentTime: timestamp)
        
        if isValley, let valleyValue = valley {
            print("检测到Valley: \(String(format: "%.2f", valleyValue)) @ \(String(format: "%.2f", timestamp))s")
            valleys.append((timestamp: timestamp, value: valleyValue))
            if valleys.count > 100 {
                valleys.removeFirst()
            }
        }
    }
    
    // 添加检查候选peaks的方法
    private func checkCandidatePeaks(currentTime: TimeInterval) {
        var i = 0
        while i < candidate_peaks.count {
            let (peak_time, peak_val) = candidate_peaks[i]
            
            // 如果当前时间已经超过了这个peak后的300ms窗口
            if currentTime >= peak_time + peak_window {
                // 清理过期的单调栈元素
                while !monotonic_stack.isEmpty && monotonic_stack[0].timestamp < peak_time - peak_window {
                    monotonic_stack.removeFirst()
                }
                
                // 检查是否是窗口内的最大值
                var is_max = true
                for (stack_time, stack_val) in monotonic_stack {
                    if abs(stack_time - peak_time) <= peak_window && stack_val > peak_val {
                        is_max = false
                        break
                    }
                }
                
                // 如果是局部最大值且与上一个选中的peak间隔足够
                if is_max && peak_time - last_selected_time >= peak_window {
                    print("选中Peak: \(String(format: "%.2f", peak_val)) @ \(String(format: "%.2f", peak_time))s")
                    selected_peaks.append((peak_time, peak_val))
                    last_selected_time = peak_time
                    
                    // 当检测到大于2的峰值时通知代理
                    if peak_val > 10.0 {
                        print("强Peak触发反馈: \(String(format: "%.2f", peak_val))")
                        delegate?.signalProcessor(self, didDetectStrongPeak: peak_val)
                    }
                }
                
                // 从单调栈中移除当前peak（如果存在）
                if !monotonic_stack.isEmpty && monotonic_stack[0].timestamp == peak_time {
                    monotonic_stack.removeFirst()
                }
                
                candidate_peaks.remove(at: i)
            } else {
                i += 1
            }
        }
    }
    
    // 获取选中的峰值
    func getSelectedPeaks() -> [(timestamp: TimeInterval, value: Double)] {
        return selected_peaks
    }
    
    // 获取最近检测到的峰值
    func getRecentPeaks() -> [(timestamp: TimeInterval, value: Double)] {
        return peaks
    }
    
    // 获取最近检测到的谷值
    func getRecentValleys() -> [(timestamp: TimeInterval, value: Double)] {
        return valleys
    }
    
    // 添加打印状态的方法
    func printStatus() {
        print("\n当前状态:")
        print("Peaks (\(peaks.count)):")
        for (time, value) in peaks.suffix(5) {  // 只打印最近5个
            print("  \(String(format: "%.2f", value)) @ \(String(format: "%.2f", time))s")
        }
        
        print("\nValleys (\(valleys.count)):")
        for (time, value) in valleys.suffix(5) {  // 只打印最近5个
            print("  \(String(format: "%.2f", value)) @ \(String(format: "%.2f", time))s")
        }
        
        print("\nSelected Peaks (\(selected_peaks.count)):")
        for (time, value) in selected_peaks.suffix(5) {  // 只打印最近5个
            print("  \(String(format: "%.2f", value)) @ \(String(format: "%.2f", time))s")
        }
        print("")
    }
}

// OneEuro 滤波器实现
class OneEuroFilter {
    private var value: Double?
    private var dx = 0.0
    private let te: Double
    private let mincutoff: Double
    private let beta: Double
    private let dcutoff: Double
    
    init(te: Double, mincutoff: Double = 1.0, beta: Double = 0.007, dcutoff: Double = 1.0) {
        self.te = te
        self.mincutoff = mincutoff
        self.beta = beta
        self.dcutoff = dcutoff
    }
    
    private func computeAlpha(_ cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / te)
    }
    
    func apply(val: Double, te: Double) -> Double {
        var result = val
        if let previousValue = value {
            let edx = (val - previousValue) / te
            dx = dx + (computeAlpha(dcutoff) * (edx - dx))
            let cutoff = mincutoff + beta * abs(dx)
            result = previousValue + computeAlpha(cutoff) * (val - previousValue)
        }
        value = result
        return result
    }
}

// 添加代理协议
protocol SignalProcessorDelegate: AnyObject {
    func signalProcessor(_ processor: SignalProcessor, didDetectStrongPeak value: Double)
} 
