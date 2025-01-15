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
    
    private init() {}
} 