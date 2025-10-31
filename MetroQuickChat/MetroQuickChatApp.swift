//
//  MetroQuickChatApp.swift
//  MetroQuickChat
//
//  Created by 王恒 on 2025/10/30.
//

import SwiftUI
import CoreBluetooth
import CoreLocation

@main
struct MetroQuickChatApp: App {
    @State private var showOnboarding = MetroQuickChatApp.needsOnboarding()
    
    init() {
        // 应用启动时请求通知权限
        Task { @MainActor in
            await NotificationService.shared.requestAuthorization()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if showOnboarding {
                    OnboardingView(onFinished: { showOnboarding = false })
                } else {
                    HomeView()
                }
            }
            .onAppear {
                // 确保通知权限已请求
                Task { @MainActor in
                    await NotificationService.shared.requestAuthorization()
                }
            }
        }
    }

    private static func needsOnboarding() -> Bool {
        if UserDefaults.standard.bool(forKey: "onboardingDone") == true { return false }
        let ble = CBManager.authorization
        let loc = CLLocationManager().authorizationStatus
        let bleOK = (ble == .allowedAlways)
        let locOK: Bool = (loc == .authorizedWhenInUse || loc == .authorizedAlways)
        return !(bleOK && locOK)
    }
}
