//
//  BlePairingView.swift
//  MicroHandGestureCollectorIWatch Watch App
//
//  Created by wayne on 2024/12/6.
//

import SwiftUI

struct BlePairingView: View {
    @StateObject private var bleService = BleCentralService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 蓝牙状态显示
                    bleStatusSection
                    
                    // 配对状态和控制
                    pairingControlSection
                    
                    // 设备列表
                    deviceListSection
                }
                .padding(.horizontal, 8)
            }
            .navigationTitle("蓝牙配对")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 蓝牙状态显示部分
    @ViewBuilder
    private var bleStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("蓝牙状态")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: bleService.isConnected ? "bolt.circle.fill" : "bolt.circle")
                        .foregroundColor(bleService.isConnected ? .blue : .gray)
                    Text(bleService.isConnected ? "已连接" : "未连接")
                        .font(.subheadline)
                    Spacer()
                }
                
                if !bleService.connectedDeviceName.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(bleService.connectedDeviceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                if !bleService.pairingMessage.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text(bleService.pairingMessage)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
    }
    
    // 配对控制部分
    @ViewBuilder
    private var pairingControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("配对控制")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                switch bleService.pairingState {
                case .idle:
                    Button("开始扫描") {
                        bleService.startScanning()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
                case .scanning:
                    VStack {
                        ProgressView("扫描设备中...")
                            .progressViewStyle(CircularProgressViewStyle())
                        Button("停止扫描") {
                            bleService.stopScanning()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    
                case .deviceFound:
                    Button("重新扫描") {
                        bleService.refreshDevices()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                case .pairingRequest, .waitingResponse:
                    VStack {
                        ProgressView("配对中...")
                            .progressViewStyle(CircularProgressViewStyle())
                        Button("取消") {
                            bleService.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    
                case .paired:
                    Button("断开连接") {
                        bleService.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                }
                
                if let error = bleService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
    }
    
    // 设备列表部分
    @ViewBuilder
    private var deviceListSection: some View {
        if !bleService.discoveredDevices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("发现的设备")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(spacing: 8) {
                    ForEach(bleService.discoveredDevices) { device in
                        Button(action: {
                            bleService.sendPairingRequest(to: device)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.primary)
                                    Text("信号强度: \(device.rssi) dBm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .disabled(bleService.pairingState == .pairingRequest || bleService.pairingState == .waitingResponse)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
        }
    }
}

#Preview {
    BlePairingView()
} 