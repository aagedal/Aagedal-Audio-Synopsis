//
//  MeetSumApp.swift
//  Audio Synopsis
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI
import MLXLMCommon
import Hub

/// FocusedValue key to expose the "new recording" action to menu commands
struct NewRecordingActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newRecordingAction: (() -> Void)? {
        get { self[NewRecordingActionKey.self] }
        set { self[NewRecordingActionKey.self] = newValue }
    }
}

@main
struct MeetSumApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var recordingStore = RecordingStore()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var llamaServerManager = LlamaServerManager()
    @FocusedValue(\.newRecordingAction) private var newRecordingAction

    init() {
        Logger.info("Audio Synopsis application starting", category: Logger.general)

        // Store MLX model downloads in Application Support instead of Caches
        // (Caches can be purged by macOS under storage pressure)
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let mlxBase = appSupport.appendingPathComponent("MLXModels")
            try? FileManager.default.createDirectory(at: mlxBase, withIntermediateDirectories: true)
            MLXLMCommon.defaultHubApi = HubApi(downloadBase: mlxBase)
        }
    }

    var body: some Scene {
        Window("Audio Synopsis", id: "main") {
            ContentView(modelManager: modelManager, recordingStore: recordingStore, chatStore: chatStore, llamaServerManager: llamaServerManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    newRecordingAction?()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newRecordingAction == nil)
            }
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(modelManager)
                .environmentObject(llamaServerManager)
        }
        .defaultSize(width: 780, height: 620)
        .windowResizability(.contentSize)
    }
}

/// Helper view to open the settings window from the menu bar (Cmd+,)
private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings...") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
