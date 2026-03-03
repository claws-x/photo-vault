//
//  PhotoVaultApp.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import SwiftUI

@main
struct PhotoVaultApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var photoManager = PhotoManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(photoManager)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // 检查 Face ID 可用性
        authManager.checkBiometricAvailability()
        
        // 加载隐私相册
        photoManager.loadAlbums()
    }
}
