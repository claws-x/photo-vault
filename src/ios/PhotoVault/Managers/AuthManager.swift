//
//  AuthManager.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import Foundation
import LocalAuthentication

/// 认证管理器
class AuthManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isLocked = true
    @Published var biometricType: LABiometryType = .none
    @Published var hasPasscode = false
    
    // MARK: - Constants
    private let passcodeKey = "vault_passcode"
    private let hasPasscodeKey = "has_passcode"
    
    // MARK: - Initialization
    init() {
        checkBiometricAvailability()
        loadPasscodeStatus()
    }
    
    // MARK: - Biometric Authentication
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }
    
    func authenticate(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        context.localizedReason = "验证身份以访问隐私照片"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: context.localizedReason) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.isLocked = false
                    completion(true, nil)
                } else {
                    completion(false, error)
                }
            }
        }
    }
    
    // MARK: - Passcode
    func setPasscode(_ passcode: String) {
        UserDefaults.standard.set(passcode, forKey: passcodeKey)
        UserDefaults.standard.set(true, forKey: hasPasscodeKey)
        hasPasscode = true
    }
    
    func verifyPasscode(_ passcode: String) -> Bool {
        guard let savedPasscode = UserDefaults.standard.string(forKey: passcodeKey) else {
            return false
        }
        return passcode == savedPasscode
    }
    
    func changePasscode(_ oldPasscode: String, newPasscode: String) -> Bool {
        guard verifyPasscode(oldPasscode) else {
            return false
        }
        setPasscode(newPasscode)
        return true
    }
    
    private func loadPasscodeStatus() {
        hasPasscode = UserDefaults.standard.bool(forKey: hasPasscodeKey)
    }
    
    // MARK: - Lock
    func lock() {
        isLocked = true
    }
    
    func unlock() {
        isLocked = false
    }
}

// MARK: - LABiometryType Extension
extension LABiometryType {
    var name: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "密码"
        @unknown default:
            return "密码"
        }
    }
}
