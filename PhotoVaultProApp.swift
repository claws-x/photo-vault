//
//  PhotoVaultProApp.swift
//  PhotoVault Pro
//
//  应用主入口 - 安全初始化与配置
//

import SwiftUI
import Combine

@main
struct PhotoVaultProApp: App {
    
    static let shared: PhotoVaultProApp = PhotoVaultProApp()
    
    @StateObject private var authManager = FaceIDAuthenticationManager.shared
    @StateObject private var vaultManager = VaultManager.shared
    @StateObject private var decoyManager = DecoyModeManager.shared
    
    @State private var showLockScreen = true
    @State private var isInDecoyMode = false
    
    init() {
        // 应用启动时的安全检查
        performSecurityChecks()
        setupCrashProtection()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView(
                showLockScreen: $showLockScreen,
                isInDecoyMode: $isInDecoyMode
            )
            .environmentObject(authManager)
            .environmentObject(vaultManager)
            .environmentObject(decoyManager)
            .onAppear {
                checkAppIntegrity()
            }
        }
    }
    
    // MARK: - 安全检查
    
    private func performSecurityChecks() {
        #if !DEBUG
        // 生产环境检查
        
        // 1. 越狱检测
        if isJailbroken() {
            NSLog("⚠️ 设备已越狱，应用功能受限")
            // 可以选择限制功能或退出应用
            // exit(0)
        }
        
        // 2. 调试器检测
        if isDebuggerAttached() {
            NSLog("⚠️ 检测到调试器")
            // 可以选择退出应用
        }
        
        // 3. 系统时间验证
        if !isSystemTimeValid() {
            NSLog("⚠️ 系统时间可能已被篡改")
        }
        
        // 4. 应用完整性检查
        if !isAppIntegrityValid() {
            NSLog("⚠️ 应用签名验证失败")
        }
        #endif
        
        // 5. 附加反调试保护
        attachAntiDebugHandler()
    }
    
    // MARK: - 崩溃保护
    
    private func setupCrashProtection() {
        // 设置 NSSetUncaughtExceptionHandler
        NSSetUncaughtExceptionHandler { exception in
            NSLog("💥 未捕获的异常：\(exception.name)")
            NSLog("原因：\(exception.reason ?? "未知")")
            NSLog("堆栈：\(exception.callStackSymbols)")
            
            // 清除敏感数据
            VaultEncryptionManager.shared.clearCachedKey()
        }
        
        // 设置信号处理 - 使用 C 函数指针
        signal(SIGSEGV, { _ in
            NSLog("💥 SIGSEGV 信号")
            VaultEncryptionManager.shared.clearCachedKey()
        } as sig_t)
        
        signal(SIGABRT, { _ in
            NSLog("💥 SIGABRT 信号")
            VaultEncryptionManager.shared.clearCachedKey()
        } as sig_t)
    }
    
    // MARK: - 应用完整性检查
    
    private func checkAppIntegrity() {
        // 定期检查应用完整性
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            if !isAppIntegrityValid() {
                NSLog("⚠️ 应用完整性检查失败")
                // 可以采取行动，如退出应用
            }
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @Binding var showLockScreen: Bool
    @Binding var isInDecoyMode: Bool
    
    @EnvironmentObject var authManager: FaceIDAuthenticationManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var decoyManager: DecoyModeManager
    
    var body: some View {
        Group {
            if showLockScreen {
                LockScreenView(
                    showLockScreen: $showLockScreen,
                    isInDecoyMode: $isInDecoyMode
                )
            } else {
                if isInDecoyMode {
                    DecoyMainView()
                } else {
                    VaultMainView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .emergencyWipeTriggered)) { _ in
            showLockScreen = true
            isInDecoyMode = false
        }
    }
}

// MARK: - 锁屏视图

struct LockScreenView: View {
    @Binding var showLockScreen: Bool
    @Binding var isInDecoyMode: Bool
    
    @EnvironmentObject var authManager: FaceIDAuthenticationManager
    @EnvironmentObject var decoyManager: DecoyModeManager
    
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            // 应用图标
            Image(systemName: "lock.shield")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("PhotoVault Pro")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("需要验证您的身份")
                .foregroundColor(.secondary)
            
            // Face ID 按钮
            Button(action: authenticateWithFaceID) {
                Image(systemName: "faceid")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)
            }
            .disabled(!authManager.isBiometryAvailable)
            
            // 密码输入
            SecureField("输入密码", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 300)
                .keyboardType(.numberPad)
            
            // 错误信息
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // 解锁按钮
            Button(action: authenticateWithPassword) {
                Text("解锁")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 300)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // 自动尝试 Face ID 认证
            if authManager.isBiometryAvailable {
                authenticateWithFaceID()
            }
        }
    }
    
    private func authenticateWithFaceID() {
        authManager.authenticate { result in
            switch result {
            case .success(let authResult):
                handleAuthenticationSuccess(authResult)
            case .failure(let error):
                handleAuthenticationFailure(error)
            }
        }
    }
    
    private func authenticateWithPassword() {
        // 检查密码触发方式
        let authMode = decoyManager.checkPasswordTrigger(password)
        
        switch authMode {
        case .decoy:
            // 伪装模式密码
            isInDecoyMode = true
            showLockScreen = false
            password = ""
            
        case .real(let realPassword):
            // 真实密码验证
            // 这里应该验证密码哈希
            // 框架示例：直接通过
            showLockScreen = false
            isInDecoyMode = false
            password = ""
            
        case .emergency:
            // 紧急密码 - 触发擦除
            showError = true
            errorMessage = "紧急模式已触发"
            password = ""
        }
    }
    
    private func handleAuthenticationSuccess(_ result: AuthenticationResult) {
        // 根据认证方式决定进入哪个模式
        switch result.method {
        case .faceID, .touchID:
            // 生物识别 - 进入真实模式
            showLockScreen = false
            isInDecoyMode = false
            
        case .passcode:
            // 密码 - 可能是伪装模式
            // 需要进一步判断
            showLockScreen = false
            
        case .emergencyPasscode:
            // 紧急密码
            break
        }
    }
    
    private func handleAuthenticationFailure(_ error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }
}

// MARK: - 伪装主视图

struct DecoyMainView: View {
    @EnvironmentObject var decoyManager: DecoyModeManager
    
    var body: some View {
        Group {
            switch decoyManager.config.enabledDecoyMode {
            case .calculator:
                DecoyCalculatorView()
            case .notes:
                DecoyNotesView()
            case .weather:
                DecoyWeatherView()
            case .news:
                DecoyNewsView()
            case .browser:
                DecoyBrowserView()
            }
        }
        .navigationBarTitle(decoyManager.config.decoyAppName)
    }
}

// MARK: - 真实主视图

struct VaultMainView: View {
    @EnvironmentObject var vaultManager: VaultManager
    
    var body: some View {
        NavigationView {
            List(vaultManager.getAlbums()) { album in
                NavigationLink(destination: AlbumDetailView(album: album)) {
                    VStack(alignment: .leading) {
                        Text(album.name)
                            .font(.headline)
                        Text("\(album.itemCount) 个项目")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("隐私相册")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: createNewAlbum) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private func createNewAlbum() {
        // 创建新相册
    }
}

// MARK: - 伪装界面视图 (简化版)

struct DecoyCalculatorView: View {
    var body: some View {
        VStack {
            Text("0")
                .font(.system(size: 60))
                .padding()
            
            LazyVGrid(columns: Array(repeating: GridItem(), count: 4)) {
                ForEach(0..<20) { i in
                    Button(action: {}) {
                        Text("\(i)")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
                    }
                }
            }
        }
    }
}

struct DecoyNotesView: View {
    @EnvironmentObject var decoyManager: DecoyModeManager
    
    var body: some View {
        List(decoyManager.getDecoyNotes()) { note in
            VStack(alignment: .leading) {
                Text(note.title)
                    .font(.headline)
                Text(note.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DecoyWeatherView: View {
    @EnvironmentObject var decoyManager: DecoyModeManager
    
    var body: some View {
        let weather = decoyManager.getDecoyWeather()
        
        VStack(spacing: 20) {
            Text(weather.location)
                .font(.title)
            
            Text("\(weather.temperature)°C")
                .font(.system(size: 80))
            
            Text(weather.condition)
                .font(.title2)
            
            Text("湿度：\(weather.humidity)%")
                .foregroundColor(.secondary)
        }
    }
}

struct DecoyNewsView: View {
    var body: some View {
        List {
            ForEach(0..<10) { i in
                VStack(alignment: .leading) {
                    Text("新闻标题 \(i + 1)")
                        .font(.headline)
                    Text("这是新闻摘要内容...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DecoyBrowserView: View {
    var body: some View {
        VStack {
            TextField("输入网址", text: .constant(""))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            WebViewPlaceholder()
        }
    }
}

struct WebViewPlaceholder: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("网页内容")
                .foregroundColor(.gray)
        }
    }
}

// MARK: - 相册详情视图

struct AlbumDetailView: View {
    let album: VaultAlbum
    
    var body: some View {
        VStack {
            Text(album.name)
                .font(.title)
            
            Text("\(album.itemCount) 个项目")
                .foregroundColor(.secondary)
            
            // 媒体网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                ForEach(0..<album.itemCount) { i in
                    Rectangle()
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(5)
                }
            }
        }
        .padding()
        .navigationTitle(album.name)
    }
}
