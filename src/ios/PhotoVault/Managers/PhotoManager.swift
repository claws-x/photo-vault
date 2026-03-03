//
//  PhotoManager.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import Foundation
import UIKit

/// 照片管理器
class PhotoManager: ObservableObject {
    // MARK: - Published Properties
    @Published var albums: [PhotoAlbum] = []
    @Published var selectedAlbum: PhotoAlbum?
    
    // MARK: - Constants
    private let albumsKey = "vault_albums"
    
    // MARK: - Initialization
    init() {
        loadAlbums()
    }
    
    // MARK: - Album Management
    func createAlbum(name: String) {
        let album = PhotoAlbum(id: UUID(), name: name, photos: [], createdAt: Date())
        albums.append(album)
        saveAlbums()
    }
    
    func deleteAlbum(at offsets: IndexSet) {
        albums.remove(atOffsets: offsets)
        saveAlbums()
    }
    
    func renameAlbum(_ album: PhotoAlbum, newName: String) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index].name = newName
            saveAlbums()
        }
    }
    
    // MARK: - Photo Management
    func addPhoto(_ photo: Photo, to album: PhotoAlbum) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index].photos.append(photo)
            saveAlbums()
        }
    }
    
    func deletePhoto(_ photo: Photo, from album: PhotoAlbum) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index].photos.removeAll { $0.id == photo.id }
            saveAlbums()
        }
    }
    
    // MARK: - Import/Export
    func importPhoto(from url: URL, to album: PhotoAlbum) {
        // 从系统相册导入照片
        if let imageData = try? Data(contentsOf: url) {
            let photo = Photo(
                id: UUID(),
                imageData: imageData,
                thumbnailData: imageData, // 简化处理
                createdAt: Date()
            )
            addPhoto(photo, to: album)
        }
    }
    
    func exportPhoto(_ photo: Photo, to url: URL) {
        // 导出照片到系统相册
        try? photo.imageData.write(to: url)
    }
    
    // MARK: - Persistence
    func loadAlbums() {
        guard let data = UserDefaults.standard.data(forKey: albumsKey),
              let loadedAlbums = try? JSONDecoder().decode([PhotoAlbum].self, from: data) else {
            return
        }
        albums = loadedAlbums
    }
    
    func saveAlbums() {
        if let data = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(data, forKey: albumsKey)
        }
    }
}

// MARK: - Data Models
struct PhotoAlbum: Identifiable, Codable {
    let id: UUID
    var name: String
    var photos: [Photo]
    let createdAt: Date
    
    var photoCount: Int {
        photos.count
    }
    
    var thumbnail: Photo? {
        photos.first
    }
}

struct Photo: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    let thumbnailData: Data
    let createdAt: Date
    
    var uiImage: UIImage? {
        UIImage(data: imageData)
    }
    
    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailData)
    }
}
