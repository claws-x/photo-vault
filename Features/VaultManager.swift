//
//  VaultManager.swift
//  PhotoVault Pro
//
//  隐私相册管理器 - 管理加密相册和媒体文件
//

import Foundation
import Photos
import Combine

// MARK: - 相册模型

struct VaultAlbum: Identifiable, Codable {
    let id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var itemCount: Int
    var isHidden: Bool  // 是否在伪装模式下隐藏
    var coverImageId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, itemCount, isHidden, coverImageId
    }
}

// MARK: - 媒体项模型

struct VaultMediaItem: Identifiable, Codable {
    let id: String
    let albumId: String
    let originalAssetId: String  // PHAsset 本地标识符
    var encryptedFilePath: String
    var thumbnailPath: String
    var mediaType: MediaType
    var createdAt: Date
    var fileSize: Int64
    var encryptionKeyRef: String  // 引用加密密钥
    
    enum MediaType: String, Codable {
        case image
        case video
        // iOS 26: livePhoto 合并到 image
    }
}

// MARK: - 相册操作错误

enum VaultError: LocalizedError {
    case albumNotFound
    case itemNotFound
    case encryptionFailed
    case decryptionFailed
    case storageFull
    case unauthorizedAccess
    case invalidOperation
    
    var errorDescription: String? {
        switch self {
        case .albumNotFound:
            return "相册不存在"
        case .itemNotFound:
            return "媒体项不存在"
        case .encryptionFailed:
            return "加密失败"
        case .decryptionFailed:
            return "解密失败"
        case .storageFull:
            return "存储空间不足"
        case .unauthorizedAccess:
            return "未授权访问"
        case .invalidOperation:
            return "无效操作"
        }
    }
}

// MARK: - 隐私相册管理器

final class VaultManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = VaultManager()
    
    // MARK: - Properties
    
    @Published private(set) var albums: [VaultAlbum] = []
    @Published private(set) var isLoading = false
    @Published private(set) var storageUsage: Int64 = 0
    @Published private(set) var totalStorageLimit: Int64 = 10 * 1024 * 1024 * 1024  // 10GB
    
    private let encryptionManager = VaultEncryptionManager.shared
    private let keychainManager = KeychainManager.shared
    private let fileManager = FileManager.default
    
    private var vaultDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("PhotoVault", isDirectory: true)
    }
    
    private var encryptedAssetsDirectory: URL {
        vaultDirectory.appendingPathComponent("encrypted_assets", isDirectory: true)
    }
    
    private var thumbnailsDirectory: URL {
        vaultDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }
    
    private let dbQueue = DispatchQueue(label: "com.photovault.db")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    private init() {
        setupDirectories()
        loadAlbums()
        setupNotifications()
    }
    
    // MARK: - 目录设置
    
    private func setupDirectories() {
        let directories = [vaultDirectory, encryptedAssetsDirectory, thumbnailsDirectory]
        
        for directory in directories {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
    }
    
    // MARK: - 相册管理
    
    /// 创建新相册
    func createAlbum(name: String, isHidden: Bool = false) throws -> VaultAlbum {
        let album = VaultAlbum(
            id: UUID().uuidString,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            itemCount: 0,
            isHidden: isHidden,
            coverImageId: nil
        )
        
        albums.append(album)
        saveAlbums()
        
        return album
    }
    
    /// 删除相册
    func deleteAlbum(_ album: VaultAlbum) throws {
        // 先删除所有媒体项
        let items = getMediaItems(albumId: album.id)
        for item in items {
            try deleteMediaItem(item)
        }
        
        // 删除相册
        albums.removeAll { $0.id == album.id }
        saveAlbums()
    }
    
    /// 更新相册
    func updateAlbum(_ album: VaultAlbum) throws {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            throw VaultError.albumNotFound
        }
        
        albums[index] = album
        saveAlbums()
    }
    
    /// 获取所有相册
    func getAlbums(includeHidden: Bool = false) -> [VaultAlbum] {
        if includeHidden {
            return albums
        } else {
            return albums.filter { !$0.isHidden }
        }
    }
    
    // MARK: - 媒体项管理
    
    /// 添加媒体项到相册
    func addMediaItem(
        to albumId: String,
        asset: PHAsset,
        completion: @escaping (Result<VaultMediaItem, Error>) -> Void
    ) {
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 从 Photo Library 导出原始文件
                let tempFileURL = try self.exportAsset(asset)
                
                // 2. 生成文件加密密钥
                let fileKey = self.encryptionManager.generateFileEncryptionKey()
                let fileKeyId = UUID().uuidString
                
                // 3. 加密文件
                let data = try Data(contentsOf: tempFileURL)
                let encryptionResult = try self.encryptionManager.encryptWithFileKey(
                    data: data,
                    fileKey: fileKey
                )
                
                // 4. 保存加密文件
                let encryptedFileName = "\(UUID().uuidString).pvenc"
                let encryptedFileURL = self.encryptedAssetsDirectory
                    .appendingPathComponent(albumId)
                    .appendingPathComponent(encryptedFileName)
                
                try self.fileManager.createDirectory(
                    at: encryptedFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try encryptionResult.encryptedData.write(to: encryptedFileURL)
                
                // 5. 生成并保存缩略图
                let thumbnailData = try self.generateThumbnail(from: asset)
                let thumbnailURL = self.thumbnailsDirectory
                    .appendingPathComponent(albumId)
                    .appendingPathComponent("\(UUID().uuidString).jpg")
                
                try? self.fileManager.createDirectory(
                    at: thumbnailURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try thumbnailData.write(to: thumbnailURL)
                
                // 6. 包装文件密钥并存储到 Keychain
                let wrappedKey = try self.encryptionManager.wrapFileKey(fileKey)
                try self.keychainManager.store(
                    data: wrappedKey,
                    identifier: "filekey_\(fileKeyId)"
                )
                
                // 7. 创建媒体项记录
                let mediaType: VaultMediaItem.MediaType
                if asset.mediaType == .video {
                    mediaType = .video
                } else {
                    mediaType = .image  // image, unknown 都作为 image 处理
                }
                
                let mediaItem = VaultMediaItem(
                    id: UUID().uuidString,
                    albumId: albumId,
                    originalAssetId: asset.localIdentifier,
                    encryptedFilePath: encryptedFileURL.path,
                    thumbnailPath: thumbnailURL.path,
                    mediaType: mediaType,
                    createdAt: Date(),
                    fileSize: Int64(encryptionResult.encryptedData.count),
                    encryptionKeyRef: fileKeyId
                )
                
                // 8. 更新相册统计
                if let albumIndex = self.albums.firstIndex(where: { $0.id == albumId }) {
                    self.albums[albumIndex].itemCount += 1
                    self.albums[albumIndex].updatedAt = Date()
                    if self.albums[albumIndex].coverImageId == nil {
                        self.albums[albumIndex].coverImageId = mediaItem.id
                    }
                }
                
                // 9. 清理临时文件
                try? self.fileManager.removeItem(at: tempFileURL)
                
                DispatchQueue.main.async {
                    self.saveAlbums()
                    self.updateStorageUsage()
                    completion(.success(mediaItem))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// 删除媒体项
    func deleteMediaItem(_ item: VaultMediaItem) throws {
        // 删除加密文件
        try? fileManager.removeItem(atPath: item.encryptedFilePath)
        
        // 删除缩略图
        try? fileManager.removeItem(atPath: item.thumbnailPath)
        
        // 删除密钥
        keychainManager.delete(identifier: "filekey_\(item.encryptionKeyRef)")
        
        // 更新相册统计
        if let albumIndex = albums.firstIndex(where: { $0.id == item.albumId }) {
            albums[albumIndex].itemCount = max(0, albums[albumIndex].itemCount - 1)
            albums[albumIndex].updatedAt = Date()
        }
        
        saveAlbums()
        updateStorageUsage()
    }
    
    /// 获取相册中的媒体项
    func getMediaItems(albumId: String) -> [VaultMediaItem] {
        // 实际实现应从数据库读取
        // 这里返回空数组作为框架示例
        return []
    }
    
    /// 解密并获取媒体文件
    func getDecryptedFile(item: VaultMediaItem, completion: @escaping (Result<URL, Error>) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 读取加密文件
                let encryptedURL = URL(fileURLWithPath: item.encryptedFilePath)
                let encryptedData = try Data(contentsOf: encryptedURL)
                
                // 2. 获取文件密钥
                let wrappedKey = try self.keychainManager.retrieveData(
                    identifier: "filekey_\(item.encryptionKeyRef)"
                )
                guard let wrappedKey = wrappedKey else {
                    throw VaultError.unauthorizedAccess
                }
                let fileKey = try self.encryptionManager.unwrapFileKey(from: wrappedKey)
                
                // 3. 解密数据
                let decryptionResult = try self.encryptionManager.decryptWithFileKey(
                    data: encryptedData,
                    fileKey: fileKey
                )
                
                // 4. 写入临时文件
                let tempURL = self.fileManager.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(item.mediaType == .video ? "mp4" : "jpg")
                
                try decryptionResult.decryptedData.write(to: tempURL)
                
                // 5. 设置文件保护
                try self.fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: tempURL.path
                )
                
                DispatchQueue.main.async {
                    completion(.success(tempURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 工具方法
    
    private func exportAsset(_ asset: PHAsset) throws -> URL {
        // 实际实现需要使用 PHImageManager 导出
        // 这里返回临时 URL 作为框架示例
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        
        // 占位实现
        try Data().write(to: tempURL)
        return tempURL
    }
    
    private func generateThumbnail(from asset: PHAsset) throws -> Data {
        // 实际实现需要生成缩略图
        // 这里返回空数据作为框架示例
        return Data()
    }
    
    private func loadAlbums() {
        // 从持久化存储加载相册
        // 框架示例：创建默认相册
        if albums.isEmpty {
            let defaultAlbum = VaultAlbum(
                id: UUID().uuidString,
                name: "个人相册",
                createdAt: Date(),
                updatedAt: Date(),
                itemCount: 0,
                isHidden: false,
                coverImageId: nil
            )
            albums.append(defaultAlbum)
        }
    }
    
    private func saveAlbums() {
        // 保存相册到持久化存储
        // 实际实现应使用 Core Data 或 SQLite
    }
    
    private func updateStorageUsage() {
        // 计算已用存储空间
        storageUsage = 0
        if let enumerator = fileManager.enumerator(
            at: encryptedAssetsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    storageUsage += Int64(fileSize)
                }
            }
        }
    }
    
    private func setupNotifications() {
        // 监听紧急擦除通知
        NotificationCenter.default.publisher(for: .emergencyWipeTriggered)
            .sink { [weak self] _ in
                self?.performEmergencyWipe()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 紧急擦除
    
    private func performEmergencyWipe() {
        NSLog("⚠️ 执行紧急数据擦除")
        
        // 1. 安全删除所有加密文件
        try? fileManager.removeItem(at: encryptedAssetsDirectory)
        
        // 2. 删除所有缩略图
        try? fileManager.removeItem(at: thumbnailsDirectory)
        
        // 3. 清除 Keychain 中的所有密钥
        keychainManager.deleteAll()
        
        // 4. 重置相册数据
        albums.removeAll()
        
        // 5. 重置存储使用量
        storageUsage = 0
        
        // 6. 重新创建目录结构
        setupDirectories()
        
        NSLog("✅ 紧急擦除完成")
    }
}

// MARK: - 伪装模式支持

extension VaultManager {
    
    /// 获取伪装模式下可见的相册
    func getDecoyAlbums() -> [VaultAlbum] {
        // 返回标记为可见的相册
        return albums.filter { !$0.isHidden }
    }
    
    /// 创建伪装相册
    func createDecoyAlbum(name: String) throws -> VaultAlbum {
        return try createAlbum(name: name, isHidden: false)
    }
    
    /// 创建隐藏相册 (真实相册)
    func createHiddenAlbum(name: String) throws -> VaultAlbum {
        return try createAlbum(name: name, isHidden: true)
    }
}
