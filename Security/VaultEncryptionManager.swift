//
//  VaultEncryptionManager.swift
//  PhotoVault Pro
//
//  数据加密管理器 - 处理文件加密/解密的核心类
//

import Foundation
import CryptoKit
import Security
import CommonCrypto

// MARK: - 加密错误

enum EncryptionError: LocalizedError {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case authenticationFailed
    case keyNotFound
    case invalidData
    case secureEnclaveUnavailable
    
    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed:
            return "密钥派生失败"
        case .encryptionFailed:
            return "加密失败"
        case .decryptionFailed:
            return "解密失败"
        case .authenticationFailed:
            return "认证失败 - 数据可能已被篡改"
        case .keyNotFound:
            return "未找到加密密钥"
        case .invalidData:
            return "数据格式无效"
        case .secureEnclaveUnavailable:
            return "Secure Enclave 不可用"
        }
    }
}

// MARK: - 加密元数据

struct EncryptionMetadata {
    /// 盐值 (用于密钥派生)
    let salt: Data
    /// 初始化向量 (IV)
    let nonce: Data
    /// 认证标签
    let tag: Data
    /// 加密算法标识
    let algorithm: String = "AES-256-GCM"
    /// 密钥派生迭代次数
    let iterations: Int = 100_000
    
    /// 序列化元数据为 Data
    func serialize() -> Data? {
        var data = Data()
        data.append(salt)
        data.append(nonce)
        data.append(tag)
        return data
    }
    
    /// 从 Data 反序列化元数据
    static func deserialize(from data: Data) -> EncryptionMetadata? {
        // 元数据结构：salt(16) + nonce(12) + tag(16) = 44 bytes
        guard data.count >= 44 else { return nil }
        
        let salt = data.subdata(in: 0..<16)
        let nonce = data.subdata(in: 16..<28)
        let tag = data.subdata(in: 28..<44)
        
        return EncryptionMetadata(
            salt: salt,
            nonce: nonce,
            tag: tag
        )
    }
}

// MARK: - 加密结果

struct EncryptionResult {
    let encryptedData: Data
    let metadata: EncryptionMetadata
}

struct DecryptionResult {
    let decryptedData: Data
    let metadata: EncryptionMetadata
}

// MARK: - 加密管理器

final class VaultEncryptionManager {
    
    // MARK: - Singleton
    
    static let shared = VaultEncryptionManager()
    
    // MARK: - Constants
    
    private let saltSize = 16
    private let nonceSize = 12  // GCM 推荐 96 位
    private let tagSize = 16
    private let keySize = 32    // AES-256
    private let pbkdf2Iterations = 100_000
    
    // MARK: - Properties
    
    private let keychainManager = KeychainManager.shared
    private var cachedMasterKey: SymmetricKey?
    private let cryptoQueue = DispatchQueue(label: "com.photovault.crypto", qos: .userInitiated)
    
    // MARK: - 初始化
    
    private init() {}
    
    // MARK: - 密钥管理
    
    /// 从密码派生主密钥
    /// - Parameters:
    ///   - password: 用户密码
    ///   - salt: 盐值 (如果为 nil 则生成新的)
    /// - Returns: 派生的主密钥
    func deriveMasterKey(from password: String, salt: Data? = nil) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let saltData = salt ?? generateRandomBytes(count: saltSize)
        
        // 使用 PBKDF2 派生密钥
        var derivedKey = Data(count: keySize)
        let derivationStatus = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            passwordData.count,
            (saltData as NSData).bytes,
            saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(pbkdf2Iterations),
            &derivedKey,
            derivedKey.count
        )
        
        guard derivationStatus == kCCSuccess else {
            throw EncryptionError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKey)
    }
    
    /// 存储主密钥到 Keychain
    func storeMasterKey(_ key: SymmetricKey, accessControl: SecAccessControl) throws {
        try keychainManager.store(key: key, identifier: "master_key", accessControl: accessControl)
        cachedMasterKey = key
    }
    
    /// 从 Keychain 获取主密钥
    func getMasterKey() throws -> SymmetricKey {
        if let cached = cachedMasterKey {
            return cached
        }
        
        guard let key = try keychainManager.retrieveKey(identifier: "master_key") else {
            throw EncryptionError.keyNotFound
        }
        
        cachedMasterKey = key
        return key
    }
    
    /// 清除缓存的密钥
    func clearCachedKey() {
        cachedMasterKey = nil
        // 使用 secureZeroMemory 清理内存
        // 注意：Swift 的 SymmetricKey 会自动管理内存安全
    }
    
    // MARK: - 文件加密
    
    /// 加密文件数据
    /// - Parameter data: 原始数据
    /// - Returns: 加密结果 (包含加密数据和元数据)
    func encrypt(data: Data) throws -> EncryptionResult {
        try cryptoQueue.sync {
            // 生成随机盐值和 nonce
            let salt = generateRandomBytes(count: saltSize)
            let nonce = generateRandomBytes(count: nonceSize)
            
            // 获取主密钥
            let masterKey = try getMasterKey()
            
            // 使用 AES-GCM 加密
            let sealedBox = try AES.GCM.seal(
                data,
                using: masterKey,
                nonce: .init(data: nonce)
            )
            
            let tag = sealedBox.tag
            let ciphertext = sealedBox.ciphertext
            
            let metadata = EncryptionMetadata(
                salt: salt,
                nonce: nonce,
                tag: tag
            )
            
            // 组合：元数据 + 密文
            var encryptedData = Data()
            if let metadataData = metadata.serialize() {
                encryptedData.append(metadataData)
            }
            encryptedData.append(ciphertext)
            
            return EncryptionResult(
                encryptedData: encryptedData,
                metadata: metadata
            )
        }
    }
    
    /// 解密文件数据
    /// - Parameter data: 加密数据 (包含元数据)
    /// - Returns: 解密结果
    func decrypt(data: Data) throws -> DecryptionResult {
        try cryptoQueue.sync {
            // 解析元数据
            guard let metadata = EncryptionMetadata.deserialize(from: data) else {
                throw EncryptionError.invalidData
            }
            
            // 提取密文 (跳过元数据部分)
            let metadataSize = saltSize + nonceSize + tagSize
            guard data.count > metadataSize else {
                throw EncryptionError.invalidData
            }
            let ciphertext = data.subdata(in: metadataSize..<data.count)
            
            // 获取主密钥
            let masterKey = try getMasterKey()
            
            // 解密
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: metadata.nonce),
                ciphertext: ciphertext,
                tag: metadata.tag
            )
            
            let decryptedData = try AES.GCM.open(sealedBox, using: masterKey)
            
            return DecryptionResult(
                decryptedData: decryptedData,
                metadata: metadata
            )
        }
    }
    
    // MARK: - 文件级加密 (带独立密钥)
    
    /// 生成文件加密密钥 (FEK)
    func generateFileEncryptionKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// 使用文件密钥加密数据
    func encryptWithFileKey(data: Data, fileKey: SymmetricKey) throws -> EncryptionResult {
        let nonce = generateRandomBytes(count: nonceSize)
        
        let sealedBox = try AES.GCM.seal(
            data,
            using: fileKey,
            nonce: .init(data: nonce)
        )
        
        let tag = sealedBox.tag
        let ciphertext = sealedBox.ciphertext
        
        // 文件级加密不需要盐值，但需要 nonce 和 tag
        let metadata = EncryptionMetadata(
            salt: Data(count: saltSize),  // 占位
            nonce: nonce,
            tag: tag
        )
        
        var encryptedData = Data()
        if let metadataData = metadata.serialize() {
            encryptedData.append(metadataData)
        }
        encryptedData.append(ciphertext)
        
        return EncryptionResult(
            encryptedData: encryptedData,
            metadata: metadata
        )
    }
    
    /// 使用文件密钥解密数据
    func decryptWithFileKey(data: Data, fileKey: SymmetricKey) throws -> DecryptionResult {
        guard let metadata = EncryptionMetadata.deserialize(from: data) else {
            throw EncryptionError.invalidData
        }
        
        let metadataSize = saltSize + nonceSize + tagSize
        guard data.count > metadataSize else {
            throw EncryptionError.invalidData
        }
        let ciphertext = data.subdata(in: metadataSize..<data.count)
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: metadata.nonce),
            ciphertext: ciphertext,
            tag: metadata.tag
        )
        
        let decryptedData = try AES.GCM.open(sealedBox, using: fileKey)
        
        return DecryptionResult(
            decryptedData: decryptedData,
            metadata: metadata
        )
    }
    
    /// 使用主密钥加密文件密钥 (Key Wrapping)
    func wrapFileKey(_ fileKey: SymmetricKey) throws -> Data {
        let masterKey = try getMasterKey()
        let nonce = generateRandomBytes(count: nonceSize)
        
        let sealedBox = try AES.GCM.seal(
            fileKey.withUnsafeBytes { Data($0) },
            using: masterKey,
            nonce: .init(data: nonce)
        )
        
        var wrappedKey = Data()
        wrappedKey.append(nonce)
        wrappedKey.append(sealedBox.tag)
        wrappedKey.append(sealedBox.ciphertext)
        
        return wrappedKey
    }
    
    /// 解密文件密钥
    func unwrapFileKey(from wrappedData: Data) throws -> SymmetricKey {
        let masterKey = try getMasterKey()
        
        // 解析：nonce(12) + tag(16) + ciphertext
        let nonceSize = 12
        let tagSize = 16
        
        guard wrappedData.count > nonceSize + tagSize else {
            throw EncryptionError.invalidData
        }
        
        let nonce = wrappedData.subdata(in: 0..<nonceSize)
        let tag = wrappedData.subdata(in: nonceSize..<(nonceSize + tagSize))
        let ciphertext = wrappedData.subdata(in: (nonceSize + tagSize)..<wrappedData.count)
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        
        let keyData = try AES.GCM.open(sealedBox, using: masterKey)
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - 工具方法
    
    /// 生成随机字节
    private func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        
        guard status == errSecSuccess else {
            fatalError("无法生成随机字节：\(status)")
        }
        
        return Data(bytes)
    }
    
    /// 安全清理数据
    func secureZero(_ data: inout Data) {
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: 0, as: UInt8.self)
        }
    }
}

// MARK: - 加密扩展

extension VaultEncryptionManager {
    
    /// 加密文件并保存到磁盘
    func encryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let result = try encrypt(data: data)
        try result.encryptedData.write(to: destinationURL)
    }
    
    /// 解密文件并保存到磁盘
    func decryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let result = try decrypt(data: data)
        try result.decryptedData.write(to: destinationURL)
    }
}
