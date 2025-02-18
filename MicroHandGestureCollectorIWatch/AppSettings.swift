import SwiftUI

@propertyWrapper
struct UserDefaultsBacked<Value> {
    let key: String
    let defaultValue: Value
    
    var wrappedValue: Value {
        get { UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @UserDefaultsBacked(key: "ossEndpoint", defaultValue: "oss-cn-shenzhen.aliyuncs.com")
    var ossEndpoint: String
    
    @UserDefaultsBacked(key: "ossBucketName", defaultValue: "wayne-oss-bucket")
    var ossBucketName: String
    
    @UserDefaultsBacked(key: "ossApiKey", defaultValue: "")
    var ossApiKey: String
    
    @UserDefaultsBacked(key: "ossApiSecret", defaultValue: "")
    var ossApiSecret: String
    
    @UserDefaultsBacked(key: "larkAppId", defaultValue: "")
    var larkAppId: String
    
    @UserDefaultsBacked(key: "larkAppSecret", defaultValue: "")
    var larkAppSecret: String
    
    @UserDefaultsBacked(key: "larkGroupName", defaultValue: "手势测试")
    var larkGroupName: String
    
    @Published var gestureMapping: [String: Set<String>] {
        didSet {
            if let data = try? JSONEncoder().encode(gestureMapping) {
                UserDefaults.standard.set(data, forKey: "gestureMapping")
            }
        }
    }
    
    @Published var armFingerMapping: [String: Set<String>] {
        didSet {
            if let data = try? JSONEncoder().encode(armFingerMapping) {
                UserDefaults.standard.set(data, forKey: "armFingerMapping")
            }
        }
    }
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: "gestureMapping"),
           let mapping = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.gestureMapping = mapping
        } else {
            self.gestureMapping = [:]
        }
        
        if let data = UserDefaults.standard.data(forKey: "armFingerMapping"),
           let mapping = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.armFingerMapping = mapping
        } else {
            self.armFingerMapping = [:]
        }
    }
} 