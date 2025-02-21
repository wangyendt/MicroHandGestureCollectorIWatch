import Foundation
import SwiftUI
import ios_tools_lib

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""
    
    @AppStorage("aiApiKey") private var apiKey = ""
    @AppStorage("aiBaseURL") private var baseURL = "https://api.deepseek.com/v1"
    @AppStorage("aiModel") private var aiModel = "deepseek-chat"
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 8192
    
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 2.0  // 设置最小请求间隔为2秒
    
    private var openAI: OpenAI {
        OpenAI(
            apiKey: apiKey,
            baseURL: baseURL
        )
    }
    private let systemPrompt = "你是一个专业、友好的AI助手。请用中文回答问题。"
    
    init() {
        print("初始化ChatViewModel")
        messages.append(ChatMessage(role: "system", content: systemPrompt))
    }
    
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !apiKey.isEmpty else {
            messages.append(ChatMessage(role: "assistant", content: "请先在设置中配置API密钥"))
            return
        }
        
        // 检查是否需要等待
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < minimumRequestInterval {
                // 等待所需的时间
                try? await Task.sleep(nanoseconds: UInt64((minimumRequestInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        
        print("发送消息: \(text)")
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        
        // 创建一个新的助手消息
        let assistantMessage = ChatMessage(role: "assistant", content: "")
        messages.append(assistantMessage)
        
        do {
            // 更新最后请求时间
            lastRequestTime = Date()
            
            var assistantResponse = ""
            try await openAI.chatStream(
                messages: messages.dropLast(),
                model: aiModel,
                temperature: AppSettings.shared.aiTemperature,
                maxTokens: aiMaxTokens
            ) { [weak self] content in
                guard let self = self else { return }
                print("收到回复片段: \(content)")
                assistantResponse += content
                
                // 使用Task在主线程更新UI
                Task { @MainActor in
                    if let index = self.messages.lastIndex(where: { $0.role == "assistant" }) {
                        self.messages[index] = ChatMessage(role: "assistant", content: assistantResponse)
                    }
                }
            }
            
            print("对话完成")
            isLoading = false
        } catch {
            print("错误: \(error)")
            isLoading = false
            if let index = messages.lastIndex(where: { $0.role == "assistant" }) {
                messages[index] = ChatMessage(role: "assistant", content: "抱歉，发生了错误：\(error.localizedDescription)")
            }
        }
    }
} 