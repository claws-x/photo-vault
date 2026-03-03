//
//  ContentView.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingPasscodeSheet = false
    
    var body: some View {
        Group {
            if authManager.isLocked {
                LockScreenView()
                    .environmentObject(authManager)
            } else {
                MainTabView()
                    .environmentObject(authManager)
            }
        }
    }
}

// MARK: - Lock Screen View
struct LockScreenView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Logo
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(hex: "#5AC8FA"))
            
            Text("PhotoVault Pro")
                .font(.title)
                .fontWeight(.bold)
            
            Text("使用 \(authManager.biometricType.name) 验证")
                .foregroundColor(.secondary)
            
            // 解锁按钮
            Button(action: authenticate) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color(hex: "#5AC8FA"))
                    .clipShape(Circle())
            }
            
            // 密码解锁
            if authManager.hasPasscode {
                Button(action: { showingPasscodeSheet = true }) {
                    Text("使用密码解锁")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .alert("认证失败", isPresented: $showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingPasscodeSheet) {
            PasscodeInputView(onVerify: { passcode in
                if authManager.verifyPasscode(passcode) {
                    authManager.unlock()
                    return true
                } else {
                    errorMessage = "密码错误"
                    showingError = true
                    return false
                }
            })
        }
    }
    
    private func authenticate() {
        authManager.authenticate { success, error in
            if !success {
                errorMessage = error?.localizedDescription ?? "认证失败"
                showingError = true
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    var body: some View {
        TabView {
            AlbumsView()
                .tabItem {
                    Image(systemName: "photo.on.rectangle.fill")
                    Text("相册")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                }
        }
        .accentColor(Color(hex: "#5AC8FA"))
    }
}

// MARK: - Passcode Input View
struct PasscodeInputView: View {
    @Environment(\.presentationMode) var presentationMode
    let onVerify: (String) -> Bool
    
    @State private var passcode = ""
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Text("输入密码")
                    .font(.title2)
                
                TextField("密码", text: $passcode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .medium))
                    .frame(height: 50)
                
                Button(action: verify) {
                    Text("确认")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#5AC8FA"))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .navigationTitle("密码解锁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("密码错误", isPresented: $showingError) {
                Button("确定", role: .cancel) { }
            }
        }
    }
    
    private func verify() {
        if onVerify(passcode) {
            presentationMode.wrappedValue.dismiss()
        } else {
            showingError = true
        }
    }
}

// MARK: - Placeholder Views
struct AlbumsView: View {
    var body: some View {
        Text("相册列表")
    }
}

struct SettingsView: View {
    var body: some View {
        Text("设置")
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
    ContentView()
        .environmentObject(AuthManager())
}
