//
//  SettingsView.swift
//  PhotoVault
//
//  Created by AIagent on 2026-03-03.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingChangePasscode = false
    @State private var showingFakeMode = false
    
    var body: some View {
        NavigationView {
            Form {
                // 安全设置
                Section(header: Text("安全设置")) {
                    HStack {
                        Text("生物识别")
                        Spacer()
                        Text(authManager.biometricType.name)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: { showingChangePasscode = true }) {
                        HStack {
                            Text("修改密码")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 伪装模式
                Section(header: Text("伪装模式")) {
                    Toggle("启用伪装模式", isOn: .constant(false))
                    
                    Button(action: { showingFakeMode = true }) {
                        HStack {
                            Text("选择伪装外观")
                            Spacer()
                            Text("计算器")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 关于
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "mailto:support@photovaultpro.com")!) {
                        HStack {
                            Text("联系支持")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 危险区域
                Section {
                    Button(action: deleteAllData) {
                        HStack {
                            Spacer()
                            Text("删除所有数据")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingChangePasscode) {
                ChangePasscodeView()
            }
        }
    }
    
    private func deleteAllData() {
        // 清空所有数据
        UserDefaults.standard.removeAll()
    }
}

// MARK: - Change Passcode View
struct ChangePasscodeView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authManager: AuthManager
    @State private var oldPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("原密码")) {
                    SecureField("输入原密码", text: $oldPasscode)
                        .keyboardType(.numberPad)
                }
                
                Section(header: Text("新密码")) {
                    SecureField("输入新密码", text: $newPasscode)
                        .keyboardType(.numberPad)
                    
                    SecureField("确认新密码", text: $confirmPasscode)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        save()
                    }
                    .disabled(oldPasscode.isEmpty || newPasscode.isEmpty || confirmPasscode.isEmpty)
                }
            }
            .alert("错误", isPresented: $showingError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func save() {
        guard authManager.verifyPasscode(oldPasscode) else {
            errorMessage = "原密码错误"
            showingError = true
            return
        }
        
        guard newPasscode == confirmPasscode else {
            errorMessage = "两次输入的新密码不一致"
            showingError = true
            return
        }
        
        authManager.setPasscode(newPasscode)
        presentationMode.wrappedValue.dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
