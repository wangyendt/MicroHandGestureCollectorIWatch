import Foundation
import AVFoundation
import UIKit
import SwiftUI

class VideoRecordingService: NSObject, ObservableObject {
    static let shared = VideoRecordingService()
    
    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var currentFolderName: String?
    private var videoOutputURL: URL?
    private let bleService = BlePeripheralService.shared
    
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    private override init() {
        super.init()
        // 异步初始化摄像头配置
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupCaptureSession()
        }
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = AVCaptureSession.Preset.low // 设置为中等质量，减小视频体积
        
        guard let captureSession = captureSession else { return }
        
        // 获取后置摄像头
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("获取后置摄像头失败")
            return
        }
        
        do {
            captureSession.beginConfiguration()
            
            // 创建视频输入
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("无法添加视频输入")
                captureSession.commitConfiguration()
                return
            }
            
            // 创建音频输入
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            }
            
            // 创建视频输出
            movieFileOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(movieFileOutput!) {
                captureSession.addOutput(movieFileOutput!)
            } else {
                print("无法添加视频输出")
                captureSession.commitConfiguration()
                return
            }
            
            // 应用当前的分辨率设置
            applyVideoSettings()
            
            captureSession.commitConfiguration()
            print("摄像头配置完成")
            
        } catch {
            print("设置视频捕获会话失败: \(error)")
        }
    }
    
    private func applyVideoSettings() {
        guard let captureSession = captureSession,
              let movieFileOutput = movieFileOutput else { return }
        
        captureSession.beginConfiguration()
        
        // 获取当前的分辨率设置
        let resolution = AppSettings.shared.videoResolution
        print("正在应用视频设置，分辨率：\(resolution)")
        
        // 设置视频质量
        switch resolution {
        case "vga640x480":
            if captureSession.canSetSessionPreset(AVCaptureSession.Preset.vga640x480) {
                captureSession.sessionPreset = AVCaptureSession.Preset.vga640x480
                print("已设置分辨率为：640x480")
            }
        case "cif352x288":
            if captureSession.canSetSessionPreset(AVCaptureSession.Preset.cif352x288) {
                captureSession.sessionPreset = AVCaptureSession.Preset.cif352x288
                print("已设置分辨率为：352x288")
            }
        default:
            if captureSession.canSetSessionPreset(AVCaptureSession.Preset.vga640x480) {
                captureSession.sessionPreset = AVCaptureSession.Preset.vga640x480
                print("已设置默认分辨率：640x480")
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    func startRecording(folderName: String) {
        guard AppSettings.shared.enableVideoRecording,
              let movieFileOutput = movieFileOutput,
              !isRecording else {
            return
        }
        
        // 在开始录制前重新应用视频设置
        applyVideoSettings()
        
        currentFolderName = folderName
        
        // 首先更新UI状态，确保界面响应
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingTime = 0
            self.recordingStartTime = Date()
            
            // 创建计时器更新录制时间
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingTime = Date().timeIntervalSince(startTime)
            }
        }
        
        // 将所有耗时操作放到后台线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 创建视频文件夹
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("无法获取文档路径")
                return
            }
            
            let videosPath = documentsPath.appendingPathComponent("Videos", isDirectory: true)
            do {
                if !FileManager.default.fileExists(atPath: videosPath.path) {
                    try FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true, attributes: nil)
                }
                
                // 创建临时文件用于录制 - 使用下划线格式而非连字符
                // 使用传入的folderName作为文件名，保持一致性
                let videoFileName = "\(folderName).mp4"
                self.videoOutputURL = videosPath.appendingPathComponent(videoFileName)
                
                // 如果文件已存在，先删除
                if FileManager.default.fileExists(atPath: self.videoOutputURL!.path) {
                    try FileManager.default.removeItem(at: self.videoOutputURL!)
                }
                
                // 启动捕获会话
                if self.captureSession?.isRunning == false {
                    self.captureSession?.startRunning()
                }
                
                // 开始录制
                DispatchQueue.main.async {
                    if let url = self.videoOutputURL {
                        self.movieFileOutput?.startRecording(to: url, recordingDelegate: self)
                        print("开始视频录制，保存到：\(url.path)")
                    }
                }
                
            } catch {
                print("准备视频录制失败: \(error)")
                // 如果失败，恢复UI状态
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                }
            }
        }
    }
    
    func stopRecording(completion: ((Bool) -> Void)? = nil) {
        guard isRecording, movieFileOutput?.isRecording == true else {
            completion?(false)
            return
        }
        
        // 停止计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // 更新状态
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        // 在后台线程停止录制
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.movieFileOutput?.stopRecording()
            print("停止视频录制")
            DispatchQueue.main.async {
                completion?(true)
            }
        }
    }
}

extension VideoRecordingService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("开始录制到文件: \(fileURL.path)")
        
        // 获取视频开始录制的时间戳并通过BLE发送
        let timestamp = Date().timeIntervalSince1970
        let message: [String: Any] = [
            "type": "phone_start_timestamp",
            "timestamp": timestamp
        ]
        bleService.sendJSONData(message)
        print("发送视频开始时间戳：\(timestamp)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("录制完成但有错误: \(error)")
        } else {
            print("录制完成: \(outputFileURL.path)")
        }
        
        // 停止捕获会话
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
    }
} 
