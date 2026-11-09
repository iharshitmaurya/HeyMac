import Foundation

/// One status model for Settings and the menu, including the action that resolves it.
struct ProtectionStatus {
    enum Action { case none, setup, face, lockScreen, apps, addApp, resume, camera }
    var title: String
    var detail: String
    var label: String
    var tone: StatusChip.Tone
    var action: Action = .none
    var actionTitle: String? = nil
}

extension AppModel {
    var hasSavedPassword: Bool { Self.uiSnapshotMode ? snapshotPasswordSaved : (runtime?.hasLoginPassword ?? false) }

    var faceStatus: ProtectionStatus {
        if let issue = startupError ?? engineError { return .init(title: "Face recognition is unavailable.", detail: issue, label: "Unavailable", tone: .warn, action: .face, actionTitle: "Review Face Setup") }
        if !setupComplete { return .init(title: "Set up face recognition.", detail: "Set up and test face recognition to unlock with your face.", label: "Not set up", tone: .warn, action: .setup, actionTitle: "Set Up Face Recognition…") }
        if !cameraAuthorized { return .init(title: "Allow camera access.", detail: "Allow camera access to use face recognition.", label: "Camera access needed", tone: .warn, action: .camera, actionTitle: "Review Camera Access…") }
        if busy { return .init(title: "Face setup is in progress.", detail: "App Lock can still use Touch ID or your Mac password.", label: "Setup in progress", tone: .idle) }
        if paused { return .init(title: "Face recognition is paused.", detail: "You can still unlock protected apps with Touch ID or your Mac password.", label: "Paused", tone: .idle, action: .resume, actionTitle: "Resume Face Recognition") }
        let title = enrolledFacesCount > 1 ? "\(enrolledFacesCount) Face IDs Enrolled" : "Your face is set up."
        let detail = enrolledFacesCount > 1 ? "\(enrolledFacesCount) Face IDs are set up to unlock your Mac." : "Face recognition was tested successfully."
        return .init(title: title, detail: detail, label: "Ready", tone: .good)
    }

    var lockStatus: ProtectionStatus {
        if !lockScreenEnabled { return .init(title: "Protection is off.", detail: "Face unlock for the Lock Screen is off.", label: "Off", tone: .idle, action: .lockScreen, actionTitle: "Review Lock Screen") }
        if !setupComplete || !cameraAuthorized || startupError != nil || engineError != nil || busy { return faceStatus }
        if !accessibilityTrusted { return .init(title: "Lock Screen face unlock needs attention.", detail: "Allow Accessibility access to enter your saved password.", label: "Setup incomplete", tone: .warn, action: .lockScreen, actionTitle: "Finish Lock Screen Setup") }
        if !hasSavedPassword || lockScreenNeedsPassword { return .init(title: "Lock Screen face unlock needs attention.", detail: lockScreenNeedsPassword ? "The saved password didn’t unlock your Mac. Update it, then try again." : "Save your Mac login password to finish setup.", label: "Needs login password", tone: .warn, action: .lockScreen, actionTitle: "Update Saved Password…") }
        if paused { return faceStatus }
        return .init(title: "Lock Screen is ready.", detail: "Face recognition is ready when you wake your Mac.", label: "Ready", tone: .good)
    }

    var appStatus: ProtectionStatus {
        if !appLockEnabled { return .init(title: "App Lock is off.", detail: "Selected apps aren’t protected while App Lock is off.", label: "Off", tone: .idle, action: .apps, actionTitle: "Review App Lock") }
        if appLockApps.isEmpty { return .init(title: "Choose apps to protect.", detail: "App Lock is on, but no apps are selected.", label: "No apps selected", tone: .warn, action: .addApp, actionTitle: "Add an App…") }
        let count = L10n.plural("App Lock protected apps", count: appLockApps.count)
        if !setupComplete || !cameraAuthorized || startupError != nil || engineError != nil || busy || paused {
            return .init(title: faceStatus.title, detail: L10n.format("%@ · Touch ID or your Mac password is available. %@", count, L10n.text(faceStatus.detail)), label: "Touch ID or password available", tone: paused ? .idle : .warn, action: faceStatus.action, actionTitle: faceStatus.actionTitle)
        }
        return .init(title: "App Lock is active.", detail: L10n.format("%@ · Face recognition, Touch ID, or your Mac password.", count), label: "Active", tone: .good)
    }

    var protectionStatus: ProtectionStatus {
        if !lockScreenEnabled && !appLockEnabled { return .init(title: "Protection is off.", detail: "Turn on Lock Screen or App Lock when you’re ready.", label: "Off", tone: .idle, action: .lockScreen, actionTitle: "Review Settings") }
        if lockScreenEnabled && lockStatus.tone == .warn { return lockStatus }
        if appLockEnabled && appStatus.tone == .warn { return appStatus }
        if paused || busy { return faceStatus }
        return .init(title: "Hey Mac is ready.", detail: [lockScreenEnabled ? "Lock Screen face unlock is ready." : nil, appLockEnabled ? L10n.plural("App Lock ready summary", count: appLockApps.count) : nil].compactMap { $0 }.joined(separator: " "), label: "Ready", tone: .good)
    }

    func perform(_ action: ProtectionStatus.Action) {
        switch action {
        case .none: break
        case .setup: openSetup()
        case .resume: setPaused(false)
        case .camera: openSystemSettings(anchor: "Privacy_Camera")
        case .face: showSettings(.face)
        case .lockScreen: showSettings(.lockScreen)
        case .apps: showSettings(.appLock)
        case .addApp: showSettings(.appLock); AppPickerState.shared.open()
        }
    }

    func showSettings(_ pane: SettingsPane) {
        openSettings()
        SettingsSelection.shared.pane = pane
    }
}
