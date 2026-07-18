//
//  PastrApp.swift
//  Pastr
//
//  Created by Ngonidzashe  Mangudya on 2026/01/06.
//

import SwiftUI

@main
struct PastrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        SentryBootstrap.start()
    }

    var body: some Scene {
        Settings {
            SettingsView(
                settings: SettingsStore.shared,
                historyStore: ClipboardHistoryStore.shared,
                hotKeyManager: HotKeyManager.shared
            )
        }
    }
}
