//
//  AlbumsView.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import SwiftUI
import PhotosUI

struct AlbumsView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @State private var showingNewAlbum = false
    @State private var selectedAlbum: PhotoAlbum?
    
    var body: some View {
        NavigationView {
            Group {
                if photoManager.albums.isEmpty {
                    EmptyStateView()
                } else {
                    albumList
                }
            }
            .navigationTitle("隐私相册")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewAlbum = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewAlbum) {
                NewAlbumSheet()
            }
            .sheet(item: $selectedAlbum) { album in
                PhotoGridView(album: album)
            }
        }
    }
    
    private var albumList: some View {
        List {
            ForEach(photoManager.albums) { album in
                AlbumRow(album: album)
                    .onTapGesture {
                        selectedAlbum = album
                    }
            }
            .onDelete(perform: deleteAlbums)
        }
        .listStyle(InsetGroupedListStyle())
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("还没有相册")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("点击右上角 + 创建第一个相册")
                .font(.system(size: 16))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Album Row
struct AlbumRow: View {
    let album: PhotoAlbum
    
    var body: some View {
        HStack(spacing: 12) {
            // 相册封面
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                if let thumbnail = album.thumbnail {
                    Image(uiImage: thumbnail.uiImage ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .medium))
                
                Text("\(album.photoCount) 张照片")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Text(album.createdAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - New Album Sheet
struct NewAlbumSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var photoManager: PhotoManager
    @State private var albumName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("相册名称")) {
                    TextField("输入相册名称", text: $albumName)
                }
            }
            .navigationTitle("新建相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        if !albumName.isEmpty {
                            photoManager.createAlbum(name: albumName)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .disabled(albumName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Photo Grid View
struct PhotoGridView: View {
    let album: PhotoAlbum
    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.presentationMode) var presentationMode
    @State private var showingImporter = false
    @State private var selectedPhoto: Photo?
    
    var body: some View {
        NavigationView {
            Group {
                if album.photos.isEmpty {
                    emptyState
                } else {
                    photoGrid
                }
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImporter = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                PhotoImporterView(album: album)
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("还没有照片")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.secondary)
            
            Button(action: { showingImporter = true }) {
                Text("导入照片")
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#5AC8FA"))
                    .cornerRadius(10)
            }
        }
    }
    
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(album.photos) { photo in
                    Button(action: { selectedPhoto = photo }) {
                        Image(uiImage: photo.uiImage ?? UIImage())
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    }
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Photo Importer View
struct PhotoImporterView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var photoManager: PhotoManager
    let album: PhotoAlbum
    
    var body: some View {
        NavigationView {
            Text("从系统相册选择照片")
                .padding()
            .navigationTitle("导入照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Photo Detail View
struct PhotoDetailView: View {
    let photo: Photo
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if let uiImage = photo.uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    AlbumsView()
        .environmentObject(PhotoManager())
}
