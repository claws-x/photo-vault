//
//  KeychainManager.swift
//  PhotoVault Pro
//
//  Keychain 管理器 - 安全存储密钥和敏感数据
//

import Foundation
import Security
import CryptoKit
import LocalAuthentication

// Security 框架常量
private let kSecAttrAccessibleWhenPasscodedThisDeviceOnly: CFString = kSecAttrAccessibleWhenPasscodedThisDeviceOnly
private let kSecAttrAccessibleWhenBiometryCurrentSet: CFString = kSecAttrAccessibleWhenBiometryCurrentSet

// MARK: - Keychain 错误

enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case invalidData
    case userCanceled
    case notAuthorized
    case secureEnclaveUnavailable
    case unknown(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "项目已存在"
        case .itemNotFound:
            return "项目未找到"
        case .invalidData:
            return "数据格式无效"
        case .userCanceled:
            return "用户取消操作"
        case .notAuthorized:
            return "未授权访问"
        case .secureEnclaveUnavailable:
            return "Secure Enclave 不可用"
        case .unknown(let status):
            return "Keychain 错误：\(status)"
        }
    }
}

// MARK: - Keychain 访问控制级别

enum KeychainAccessibility {
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
    case whenPasscodedThisDeviceOnly
    case whenBiometryThisDeviceOnly
    
    var secAttribute: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenPasscodedThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodedThisDeviceOnly
        case .whenBiometryThisDeviceOnly:
            return kSecAttrAccessibleWhenBiometryCurrentSet
        }
    }
}

// MARK: - Keychain 管理器

final class KeychainManager {
    
    // MARK: - Singleton
    
    static let shared = KeychainManager()
    
    // MARK: - Constants
    
    private let serviceName = "com.photovault.pro"
    private let accessGroup: String? = nil  // 如需 App Group 共享则配置
    
    // MARK: - 初始化
    
    private init() {}
    
    // MARK: - 存储对称密钥
    
    /// 存储对称密钥到 Keychain (使用 Secure Enclave 保护)
    /// - Parameters:
    ///   - key: 要存储的密钥
    ///   - identifier: 密钥标识符
    ///   - accessControl: 访问控制策略
    func store(key: SymmetricKey, identifier: String, accessControl: SecAccessControl) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try store(data: keyData, identifier: identifier, accessControl: accessControl)
    }
    
    /// 存储对称密钥到 Keychain (基础版本)
    func store(key: SymmetricKey, identifier: String, accessibility: KeychainAccessibility = .whenPasscodedThisDeviceOnly) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try store(data: keyData, identifier: identifier, accessibility: accessibility)
    }
    
    // MARK: - 存储数据
    
    /// 存储数据到 Keychain (使用 Secure Enclave 访问控制)
    func store(data: Data, identifier: String, accessControl: SecAccessControl) throws {
        // 删除已存在的项
        delete(identifier: identifier)
        
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: identifier,
            kSecValueData: data,
            kSecAttrAccessControl: accessControl,
            kSecUseDataProtectionKeychain: true
        ]
        
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.from(status: status)
        }
    }
    
    /// 存储数据到 Keychain (基础版本)
    func store(data: Data, identifier: String, accessibility: KeychainAccessibility = .whenPasscodedThisDeviceOnly) throws {
        // 删除已存在的项
        delete(identifier: identifier)
        
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: identifier,
            kSecValueData: data,
            kSecAttrAccessible: accessibility.secAttribute,
            kSecUseDataProtectionKeychain: true
        ]
        
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.from(status: status)
        }
    }
    
    // MARK: - 检索数据
    
    /// 检索对称密钥
    func retrieveKey(identifier: String) throws -> SymmetricKey? {
        guard let data = try retrieveData(identifier: identifier) else {
            return nil
        }
        return SymmetricKey(data: data)
    }
    
    /// 检索数据
    func retrieveData(identifier: String) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: identifier,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true
        ]
        
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.from(status: status)
        }
    }
    
    // MARK: - 更新数据
    
    /// 更新 Keychain 中的数据
    func update(data: Data, identifier: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: identifier
        ]
        
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.from(status: status)
        }
    }
    
    // MARK: - 删除数据
    
    /// 删除 Keychain 中的项
    func delete(identifier: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: identifier
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    /// 删除所有 PhotoVault 相关的 Keychain 项
    func deleteAll() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Secure Enclave 访问控制创建
    
    /// 创建 Secure Enclave 访问控制策略
    /// - Parameter policy: 生物识别策略
    /// - Returns: SecAccessControl 对象
    func createAccessControl(with policy: LAAccessControlOperation) -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        
        let flags: SecAccessControlCreateFlags
        switch policy {
        case .devicePasscode:
            flags = .devicePasscode
        case .biometryAny:
            flags = .biometryAny
        case .biometryCurrentSet:
            flags = .biometryCurrentSet
        case .devicePasscodeAndBiometry:
            flags = [.devicePasscode, .biometryCurrentSet]
        }
        
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodedThisDeviceOnly,
            flags,
            &error
        )
        
        if let error = error {
            NSLog("创建访问控制失败：\(error.takeRetainedValue())")
            return nil
        }
        
        return accessControl
    }
    
    /// 创建带生物识别的访问控制
    func createBiometryAccessControl() -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenBiometryCurrentSet,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        )
        
        if let error = error {
            NSLog("创建生物识别访问控制失败：\(error.takeRetainedValue())")
            return nil
        }
        
        return accessControl
    }
}

// MARK: - KeychainError Extension

extension KeychainError {
    static func from(status: OSStatus) -> KeychainError {
        switch status {
        case errSecSuccess:
            return .unknown(status)
        case errSecDuplicateItem:
            return .duplicateItem
        case errSecItemNotFound:
            return .itemNotFound
        case errSecUserCanceled:
            return .userCanceled
        case -67583, -67581: // kSecErrNotAuthorized
            return .notAuthorized
        case -67579, -67578, -67577: // Secure Enclave errors
            return .secureEnclaveUnavailable
        default:
            return .unknown(status)
        }
    }
}

// MARK: - LAAccessControlOperation Extension

extension LAAccessControlOperation {
    var secAccessControl: SecAccessControlCreateFlags {
        switch self {
        case .devicePasscode:
            return .devicePasscode
        case .biometryAny:
            return .biometryAny
        case .biometryCurrentSet:
            return .biometryCurrentSet
        case .devicePasscodeAndBiometry:
            return [.devicePasscode, .biometryCurrentSet]
        @unknown default:
            return .devicePasscode
        }
    }
}

// LAAccessControlOperation 枚举兼容 iOS 26
enum LAAccessControlOperation: Int {
    case devicePasscode = 0
    case biometryAny = 1
    case biometryCurrentSet = 2
    case devicePasscodeAndBiometry = 3
}

// MARK: - 使用示例

/*
 
 // 创建 Secure Enclave 保护的密钥
 let accessControl = KeychainManager.shared.createBiometryAccessControl()
 
 // 生成并存储主密钥
 let masterKey = SymmetricKey(size: .bits256)
 try KeychainManager.shared.store(
     key: masterKey,
     identifier: "master_key",
     accessControl: accessControl!
 )
 
 // 检索密钥 (需要生物识别认证)
 let retrievedKey = try KeychainManager.shared.retrieveKey(identifier: "master_key")
 
 // 删除密钥
 KeychainManager.shared.delete(identifier: "master_key")
 
 */
