//
//  DecoyModeManager.swift
//  PhotoVault Pro
//
//  伪装模式管理器 - 管理伪装界面和秘密访问
//

import Foundation
import UIKit
import Combine

// MARK: - 伪装模式类型

enum DecoyMode: String, Codable, CaseIterable {
    case calculator = "计算器"
    case notes = "笔记"
    case weather = "天气"
    case news = "新闻"
    case browser = "浏览器"
    
    var icon: String {
        switch self {
        case .calculator: return "plus.forwardslash.minus"
        case .notes: return "note.text"
        case .weather: return "cloud.sun"
        case .news: return "newspaper"
        case .browser: return "globe"
        }
    }
    
    var displayName: String {
        switch self {
        case .calculator: return "简易计算器"
        case .notes: return "快速笔记"
        case .weather: return "天气预报"
        case .news: return "每日新闻"
        case .browser: return "网页浏览"
        }
    }
}

// MARK: - 秘密触发方式

enum SecretTrigger: Codable {
    case gesture(GesturePattern)
    case passwordPrefix(String)
    case emergencyPassword(String)
    case biometricFinger(Int)  // 特定手指
    
    enum GesturePattern: Codable {
        case fourCorners  // 四角点击
        case doubleTap    // 双击特定区域
        case longPress    // 长按
        case custom([CGPoint])  // 自定义手势
    }
}

// MARK: - 伪装模式配置

struct DecoyConfig: Codable {
    /// 启用的伪装模式
    var enabledDecoyMode: DecoyMode = .calculator
    /// 秘密触发方式
    var secretTriggers: [SecretTrigger] = []
    /// 紧急密码 (触发擦除)
    var emergencyPassword: String?
    /// 紧急密码触发擦除
    var emergencyPasswordTriggersWipe = false
    /// 伪装模式下显示通知
    var showNotificationsInDecoy = true
    /// 伪装模式应用名称
    var decoyAppName: String = "计算器"
    /// 伪装模式应用图标
    var decoyAppIcon: String = "plus.forwardslash.minus"
}

// MARK: - 伪装模式管理器

final class DecoyModeManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = DecoyModeManager()
    
    // MARK: - Properties
    
    @Published private(set) var isDecoyModeActive = false
    @Published private(set) var config: DecoyConfig = DecoyConfig()
    @Published private(set) var lastTriggerTime: Date?
    
    private let authManager = FaceIDAuthenticationManager.shared
    private let vaultManager = VaultManager.shared
    private let keychainManager = KeychainManager.shared
    
    private let configKey = "decoy_config"
    private var cancellables = Set<AnyCancellable>()
    
    // 手势识别
    private var touchPoints: [CGPoint] = []
    private var touchTimer: Timer?
    
    // MARK: - 初始化
    
    private init() {
        loadConfig()
        setupNotifications()
    }
    
    // MARK: - 配置管理
    
    /// 加载配置
    func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(DecoyConfig.self, from: data) {
            config = decoded
        } else {
            // 默认配置
            config = DecoyConfig(
                enabledDecoyMode: .calculator,
                secretTriggers: [
                    .passwordPrefix("#"),
                    .gesture(.fourCorners)
                ],
                emergencyPassword: nil,
                emergencyPasswordTriggersWipe: false
            )
        }
    }
    
    /// 保存配置
    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }
    
    // MARK: - 模式切换
    
    /// 激活伪装模式
    func activateDecoyMode() {
        isDecoyModeActive = true
        lastTriggerTime = Date()
        
        // 更新应用外观
        updateAppAppearance(for: config.enabledDecoyMode)
        
        NSLog("🎭 伪装模式已激活：\(config.enabledDecoyMode.displayName)")
    }
    
    /// 停用伪装模式 (进入真实模式)
    func deactivateDecoyMode() {
        isDecoyModeActive = false
        
        // 恢复真实应用外观
        restoreRealAppearance()
        
        NSLog("🔓 伪装模式已停用")
    }
    
    /// 切换模式
    func toggleMode() {
        if isDecoyModeActive {
            deactivateDecoyMode()
        } else {
            activateDecoyMode()
        }
    }
    
    // MARK: - 秘密触发检测
    
    /// 检测密码前缀触发
    func checkPasswordTrigger(_ password: String) -> AuthenticationMode {
        // 检查紧急密码
        if let emergencyPassword = config.emergencyPassword,
           password == emergencyPassword {
            if config.emergencyPasswordTriggersWipe {
                // 触发紧急擦除
                NotificationCenter.default.post(name: .emergencyWipeTriggered, object: nil)
            }
            return .emergency
        }
        
        // 检查秘密前缀
        for trigger in config.secretTriggers {
            if case .passwordPrefix(let prefix) = trigger {
                if password.hasPrefix(prefix) {
                    // 真实密码 = 去掉前缀的部分
                    let realPassword = String(password.dropFirst(prefix.count))
                    return .real(password: realPassword)
                }
            }
        }
        
        return .decoy
    }
    
    /// 处理触摸事件 (检测手势)
    func handleTouch(at point: CGPoint, in view: UIView, type: TouchType) -> AuthenticationMode? {
        switch type {
        case .began:
            touchPoints = [point]
            startTouchTimer()
            
        case .moved:
            if let lastPoint = touchPoints.last {
                let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
                if distance > 10 {  // 最小移动距离
                    touchPoints.append(point)
                }
            }
            
        case .ended:
            stopTouchTimer()
            return checkGesturePattern(touchPoints, in: view)
            
        case .cancelled:
            stopTouchTimer()
            touchPoints = []
        }
        
        return nil
    }
    
    /// 检查四角点击手势
    private func checkGesturePattern(_ points: [CGPoint], in view: UIView) -> AuthenticationMode? {
        // 检测四角点击
        if case .fourCorners = config.secretTriggers.compactMap({
            if case .gesture(let g) = $0 { return g }
            return nil
        }).first {
            let bounds = view.bounds
            let cornerSize = CGSize(width: bounds.width * 0.3, height: bounds.height * 0.3)
            
            // 定义四个角落区域
            let topLeft = CGRect(origin: .zero, size: cornerSize)
            let topRight = CGRect(
                x: bounds.width - cornerSize.width,
                y: 0,
                width: cornerSize.width,
                height: cornerSize.height
            )
            let bottomLeft = CGRect(
                x: 0,
                y: bounds.height - cornerSize.height,
                width: cornerSize.width,
                height: cornerSize.height
            )
            let bottomRight = CGRect(
                x: bounds.width - cornerSize.width,
                y: bounds.height - cornerSize.height,
                width: cornerSize.width,
                height: cornerSize.height
            )
            
            // 检查是否按顺序点击了四个角
            if points.count >= 4 {
                let corners = [topLeft, topRight, bottomLeft, bottomRight]
                var cornerIndex = 0
                
                for point in points {
                    if corners[cornerIndex].contains(point) {
                        cornerIndex += 1
                        if cornerIndex >= 4 {
                            NSLog("🔑 检测到四角手势 - 进入真实模式")
                            return .real(password: nil)
                        }
                    } else {
                        cornerIndex = 0
                    }
                }
            }
        }
        
        return nil
    }
    
    private func startTouchTimer() {
        touchTimer?.invalidate()
        touchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.touchPoints = []
        }
    }
    
    private func stopTouchTimer() {
        touchTimer?.invalidate()
        touchTimer = nil
    }
    
    // MARK: - 生物识别触发
    
    /// 检测特定手指 (需要 Touch ID)
    func checkBiometricFinger(_ fingerIndex: Int) -> Bool {
        // 注意：iOS 不提供具体手指识别
        // 这是一个概念实现，实际需要使用其他方法
        guard case .biometricFinger(let targetFinger) = config.secretTriggers.compactMap({
            if case .biometricFinger(let f) = $0 { return $0 }
            return nil
        }).first else {
            return false
        }
        
        return fingerIndex == targetFinger
    }
    
    // MARK: - 外观管理
    
    private func updateAppAppearance(for mode: DecoyMode) {
        // 更新应用名称
        if let displayName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String {
            // 保存原始名称
            UserDefaults.standard.set(displayName, forKey: "original_app_name")
        }
        
        // 更新主题色
        updateThemeColor(for: mode)
        
        // 更新图标 (需要重新构建或使用动态图标)
        // 注意：动态更改应用图标需要 iOS 10.3+ 和用户确认
    }
    
    private func updateThemeColor(for mode: DecoyMode) {
        let color: UIColor
        switch mode {
        case .calculator:
            color = UIColor.systemGray
        case .notes:
            color = UIColor.systemYellow
        case .weather:
            color = UIColor.systemBlue
        case .news:
            color = UIColor.systemOrange
        case .browser:
            color = UIColor.systemGreen
        }
        
        // 更新 UIWindow 的 tint color
        NotificationCenter.default.post(
            name: .updateThemeColor,
            object: color
        )
    }
    
    private func restoreRealAppearance() {
        // 恢复原始应用名称
        if let originalName = UserDefaults.standard.string(forKey: "original_app_name") {
            // 注意：应用名称无法在运行时更改，需要重启应用
            NSLog("原始应用名称：\(originalName)")
        }
        
        // 恢复原始主题色
        NotificationCenter.default.post(
            name: .updateThemeColor,
            object: UIColor.systemPurple  // PhotoVault 主题色
        )
    }
    
    // MARK: - 伪装界面数据
    
    /// 获取伪装计算器显示
    func getDecoyCalculatorDisplay() -> String {
        // 返回随机计算结果
        let operations = ["12 + 35", "128 / 4", "45 * 2", "100 - 23"]
        let randomOp = operations.randomElement() ?? "12 + 35"
        return randomOp
    }
    
    /// 获取伪装笔记列表
    func getDecoyNotes() -> [DecoyNote] {
        return [
            DecoyNote(title: "购物清单", content: "牛奶，鸡蛋，面包", date: Date()),
            DecoyNote(title: "会议记录", content: "下周项目评审", date: Date().addingTimeInterval(-86400)),
            DecoyNote(title: "想法", content: "新的产品创意...", date: Date().addingTimeInterval(-172800))
        ]
    }
    
    /// 获取伪装天气数据
    func getDecoyWeather() -> DecoyWeather {
        return DecoyWeather(
            location: "东京",
            temperature: 22,
            condition: "晴",
            humidity: 65
        )
    }
    
    // MARK: - 通知监听
    
    private func setupNotifications() {
        // 监听应用进入后台
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                // 进入后台时自动切换到伪装模式
                self?.activateDecoyMode()
            }
            .store(in: &cancellables)
        
        // 监听设备摇动 (可选的快速切换)
        NotificationCenter.default.publisher(for: .deviceShaken)
            .sink { [weak self] _ in
                // 摇动设备快速切换模式 (开发调试用)
                #if DEBUG
                self?.toggleMode()
                #endif
            }
            .store(in: &cancellables)
    }
}

// MARK: - 辅助类型

enum AuthenticationMode {
    case decoy  // 伪装模式
    case real(password: String?)  // 真实模式
    case emergency  // 紧急模式 (触发擦除)
}

enum TouchType {
    case began
    case moved
    case ended
    case cancelled
}

struct DecoyNote: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let date: Date
}

struct DecoyWeather {
    let location: String
    let temperature: Int
    let condition: String
    let humidity: Int
}

// MARK: - Notification Names

extension Notification.Name {
    static let updateThemeColor = Notification.Name("updateThemeColor")
    static let deviceShaken = Notification.Name("deviceShaken")
}

// MARK: - 使用示例

/*
 
 // 在 ViewController 中集成伪装模式
 
 class DecoyViewController: UIViewController {
     
     override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
         guard let touch = touches.first else { return }
         let location = touch.location(in: view)
         
         if let mode = DecoyModeManager.shared.handleTouch(
             at: location,
             in: view,
             type: .began
         ) {
             handleAuthenticationMode(mode)
         }
     }
     
     override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
         guard let touch = touches.first else { return }
         let location = touch.location(in: view)
         
         DecoyModeManager.shared.handleTouch(
             at: location,
             in: view,
             type: .moved
         )
     }
     
     override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
         guard let touch = touches.first else { return }
         let location = touch.location(in: view)
         
         if let mode = DecoyModeManager.shared.handleTouch(
             at: location,
             in: view,
             type: .ended
         ) {
             handleAuthenticationMode(mode)
         }
     }
     
     private func handleAuthenticationMode(_ mode: AuthenticationMode) {
         switch mode {
         case .decoy:
             // 保持伪装界面
             break
         case .real(let password):
             // 进入真实模式
             authenticateAndEnterVault(password: password)
         case .emergency:
             // 触发紧急擦除
             showEmergencyAlert()
         }
     }
 }
 
 */
