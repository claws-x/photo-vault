//
//  CryptoManager.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import Foundation
import CommonCrypto

/// 加密管理器 - 真实 AES-256 加密
class CryptoManager {
    static let shared = CryptoManager()
    
    private let keySize = kCCKeySizeAES256
    private let key: Data
    
    private init() {
        key = loadOrGenerateKey()
    }
    
    // MARK: - 加密 - 真实加密
    func encrypt(_ data: Data) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesEncrypted: size_t = 0
        
        let status = buffer.withUnsafeMutableBytes { encryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, keySize,
                        nil,
                        dataBytes.baseAddress, data.count,
                        encryptedBytes.baseAddress, bufferSize,
                        &numBytesEncrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.encryptionFailed
        }
        
        buffer.count = numBytesEncrypted
        return buffer
    }
    
    // MARK: - 解密 - 真实解密
    func decrypt(_ data: Data) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0
        
        let status = buffer.withUnsafeMutableBytes { decryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, keySize,
                        nil,
                        dataBytes.baseAddress, data.count,
                        decryptedBytes.baseAddress, bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.decryptionFailed
        }
        
        buffer.count = numBytesDecrypted
        return buffer
    }
    
    // MARK: - 密钥管理 - Keychain 安全存储
    private func loadOrGenerateKey() -> Data {
        let keychainKey = "photovault_encryption_key"
        
        // 尝试从 Keychain 加载
        if let existingKey = try? KeychainHelper.load(key: keychainKey) {
            return existingKey
        }
        
        // 生成新密钥
        var key = Data(count: keySize)
        let status = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, keySize, bytes.baseAddress!)
        }
        
        guard status == errSecSuccess else {
            fatalError("Failed to generate encryption key")
        }
        
        // 保存到 Keychain
        try? KeychainHelper.save(key: keychainKey, data: key)
        
        return key
    }
}

// MARK: - 加密错误
enum CryptoError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "加密失败"
        case .decryptionFailed: return "解密失败"
        }
    }
}

// MARK: - Keychain 助手 - 安全存储
class KeychainHelper {
    static func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }
    
    static func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeychainError.loadFailed
        }
        
        return data
    }
}

enum KeychainError: LocalizedError {
    case saveFailed
    case loadFailed
    
    var errorDescription: String? {
        switch self {
        case .saveFailed: return "Keychain 保存失败"
        case .loadFailed: return "Keychain 加载失败"
        }
    }
}
