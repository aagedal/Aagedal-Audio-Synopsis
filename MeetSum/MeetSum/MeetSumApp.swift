//
//  MeetSumApp.swift
//  MeetSum
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI

/// FocusedValue key to expose the "new meeting" action to menu commands
struct NewMeetingActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newMeetingAction: (() -> Void)? {
        get { self[NewMeetingActionKey.self] }
        set { self[NewMeetingActionKey.self] = newValue }
    }
}

@main
struct MeetSumApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var meetingStore = MeetingStore()
    @FocusedValue(\.newMeetingAction) private var newMeetingAction

    init() {
        Logger.info("MeetSum application starting", category: Logger.general)
    }

    var body: some Scene {
        Window("MeetSum", id: "main") {
            ContentView(modelManager: modelManager, meetingStore: meetingStore)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Meeting") {
                    newMeetingAction?()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newMeetingAction == nil)
            }
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(modelManager)
        }
        .defaultSize(width: 650, height: 550)
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
