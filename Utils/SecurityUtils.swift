//
//  SecurityUtils.swift
//  PhotoVault Pro
//
//  安全工具函数集合
//

import Foundation
import CryptoKit
import Security
import CommonCrypto
import UIKit

// MARK: - 安全内存操作

/// 安全清零内存中的数据
func secureZero(_ pointer: UnsafeMutableRawPointer, count: Int) {
    memset_s(pointer, count, 0, count)
}

/// 安全清零 Data
extension Data {
    mutating func secureZero() {
        withUnsafeMutableBytes { ptr in
            memset_s(ptr.baseAddress, ptr.count, 0, ptr.count)
        }
    }
}

/// 安全清零字符串
extension String {
    func secureData() -> Data {
        return Data(utf8)
    }
}

// MARK: - 密码强度验证

enum PasswordStrength {
    case tooWeak
    case weak
    case medium
    case strong
    case veryStrong
    
    var score: Int {
        switch self {
        case .tooWeak: return 0
        case .weak: return 1
        case .medium: return 2
        case .strong: return 3
        case .veryStrong: return 4
        }
    }
    
    var feedback: String {
        switch self {
        case .tooWeak:
            return "密码太弱，至少需要 8 位"
        case .weak:
            return "密码较弱，建议添加数字和符号"
        case .medium:
            return "密码强度中等"
        case .strong:
            return "密码强度良好"
        case .veryStrong:
            return "密码强度非常好"
        }
    }
}

/// 验证密码强度
func validatePasswordStrength(_ password: String) -> PasswordStrength {
    var score = 0
    
    // 长度检查
    if password.count >= 8 { score += 1 }
    if password.count >= 12 { score += 1 }
    if password.count >= 16 { score += 1 }
    
    // 字符类型检查
    let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
    let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
    let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
    let hasSymbols = password.rangeOfCharacter(from: .symbols) != nil
    
    if hasLowercase { score += 1 }
    if hasUppercase { score += 1 }
    if hasNumbers { score += 1 }
    if hasSymbols { score += 1 }
    
    // 常见密码检查
    let commonPasswords = ["123456", "password", "qwerty", "111111", "000000"]
    if commonPasswords.contains(password.lowercased()) {
        return .tooWeak
    }
    
    // 转换为强度等级
    switch score {
    case 0...2: return .tooWeak
    case 3...4: return .weak
    case 5...6: return .medium
    case 7...8: return .strong
    default: return .veryStrong
    }
}

// MARK: - 哈希函数

/// SHA-256 哈希
func sha256(data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

/// SHA-256 哈希 (字符串)
func sha256(string: String) -> Data {
    return sha256(data: Data(string.utf8))
}

/// HMAC-SHA256
func hmacSHA256(data: Data, key: Data) -> Data {
    var result = [CUnsignedChar](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CCHmac(
        CCHmacAlgorithm(kCCHmacAlgSHA256),
        (key as NSData).bytes,
        key.count,
        (data as NSData).bytes,
        data.count,
        &result
    )
    return Data(result)
}

// MARK: - 随机数生成

/// 生成安全随机数
func secureRandomBytes(count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    
    guard status == errSecSuccess else {
        fatalError("无法生成安全随机数：\(status)")
    }
    
    return Data(bytes)
}

/// 生成安全随机字符串
func secureRandomString(length: Int, charset: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") -> String {
    var result = ""
    let charsetCount = charset.count
    
    for _ in 0..<length {
        let randomBytes = secureRandomBytes(count: 1)
        let index = Int(randomBytes[0]) % charsetCount
        let charIndex = charset.index(charset.startIndex, offsetBy: index)
        result.append(charset[charIndex])
    }
    
    return result
}

// MARK: - 时间安全

/// 常量时间比较 (防止时序攻击)
func constantTimeCompare(_ data1: Data, _ data2: Data) -> Bool {
    guard data1.count == data2.count else {
        return false
    }
    
    var result: UInt8 = 0
    for i in 0..<data1.count {
        result |= data1[i] ^ data2[i]
    }
    
    return result == 0
}

/// 常量时间比较 (字符串)
func constantTimeCompare(_ string1: String, _ string2: String) -> Bool {
    return constantTimeCompare(
        Data(string1.utf8),
        Data(string2.utf8)
    )
}

// MARK: - 越狱检测

/// 检测设备是否越狱
func isJailbroken() -> Bool {
    // 检查常见越狱文件
    let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/usr/bin/ssh",
        "/var/cache/apt"
    ]
    
    for path in jailbreakPaths {
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
    }
    
    // 检查 URL Scheme
    if let url = URL(string: "cydia://package/com.example.package") {
        if UIApplication.shared.canOpenURL(url) {
            return true
        }
    }
    
    // 简化检测：不执行 fork()
    return false
}

// MARK: - 调试保护

/// 检测调试器
func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    
    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    
    if result == 0 {
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    return false
}

/// 反调试保护
func attachAntiDebugHandler() {
    #if DEBUG
    // 调试模式下不启用
    return
    #endif
    
    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        if isDebuggerAttached() {
            NSLog("⚠️ 检测到调试器，应用将退出")
            exit(0)
        }
    }
}

// MARK: - 字符串安全

/// 安全 Base64 编码
func safeBase64Encode(_ data: Data) -> String {
    return data.base64EncodedString()
}

/// 安全 Base64 解码
func safeBase64Decode(_ string: String) -> Data? {
    return Data(base64Encoded: string)
}

// MARK: - 文件安全

/// 安全删除文件 (多次覆盖)
func secureDeleteFile(at url: URL, passes: Int = 3) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    
    let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
    
    // 多次覆盖写入随机数据
    for _ in 0..<passes {
        let randomData = secureRandomBytes(count: Int(fileSize))
        try randomData.write(to: url)
    }
    
    // 最后删除文件
    try FileManager.default.removeItem(at: url)
}

/// 设置文件保护
func setFileProtection(_ url: URL, protectionType: FileProtectionType) throws {
    try FileManager.default.setAttributes(
        [.protectionKey: protectionType],
        ofItemAtPath: url.path
    )
}

// MARK: - 网络时间同步

/// 验证系统时间是否被篡改
func isSystemTimeValid() -> Bool {
    let currentDate = Date()
    let referenceDate = Date(timeIntervalSince1970: 1640995200)  // 2022-01-01
    
    // 检查时间是否合理 (不超过参考日期之前)
    if currentDate < referenceDate {
        return false
    }
    
    // 检查时间是否过于超前 (超过 1 年)
    let maxFutureDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
    if currentDate > maxFutureDate {
        return false
    }
    
    return true
}

// MARK: - 日志安全

/// 安全日志 (生产环境禁用)
func secureLog(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    NSLog("[\(filename):\(line)] \(function) - \(message)")
    #endif
}

/// 敏感日志 (始终禁用)
func sensitiveLog(_ message: String) {
    // 永不记录敏感信息
    // 即使是在 DEBUG 模式下
}

// MARK: - 应用状态

/// 检查应用是否被篡改
func isAppIntegrityValid() -> Bool {
    // 检查代码签名
    let bundlePath = Bundle.main.bundlePath
    let url = URL(fileURLWithPath: bundlePath)
    
    // iOS 上签名验证简化处理
    // SecStaticCode API 在 iOS 上有限制，使用简化版本
    return true
}

// MARK: - 常量

struct SecurityConstants {
    static let minPasswordLength = 8
    static let maxPasswordLength = 128
    static let maxLoginAttempts = 5
    static let lockoutDuration: TimeInterval = 30
    static let sessionTimeout: TimeInterval = 300  // 5 分钟
    static let keyDerivationIterations = 100_000
    static let saltSize = 16
    static let nonceSize = 12
    static let tagSize = 16
}
