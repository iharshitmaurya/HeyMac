import Foundation
import Testing
import HeyMacEngine
@testable import HeyMacApp

/// Runs the actual UI state/route code without a runtime, camera, credentials, or saved-setting writes.
@MainActor @Suite(.serialized)
struct ReleaseStateTests {
    private func sample(_ scenario: String = "ready") throws -> AppModel {
        AppModel.uiSnapshotMode = true
        let model = AppModel.shared
        precondition(model.runtime == nil)
        let apps = try JSONDecoder().decode([LockedApp].self, from: Data(#"[{"bundleID":"com.apple.Notes","name":"Notes","policy":{"everyTime":{}}}]"#.utf8))
        model.configureSnapshot(scenario, apps: apps)
        return model
    }

    @Test func readyRequiresConfiguredProtection() throws {
        let model = try sample()
        #expect(model.protectionStatus.label == "Ready")
        #expect(model.lockStatus.label == "Ready")
        #expect(model.appStatus.label == "Active")
    }
    @Test func protectionOffDoesNotClaimReady() throws {
        let model = try sample("off")
        #expect(model.protectionStatus.label == "Off")
        #expect(model.lockStatus.label == "Off")
        #expect(model.appStatus.label == "Off")
    }
    @Test func pauseOffersResumeAndSystemAuthFallback() throws {
        let model = try sample("paused")
        #expect(model.protectionStatus.label == "Paused")
        #expect(model.protectionStatus.action == .resume)
        #expect(model.lockStatus.label == "Paused")
        #expect(model.appStatus.label == "Touch ID or password available")
    }
    @Test func missingCameraRoutesToCameraAccess() throws {
        let model = try sample("camera-denied")
        #expect(model.protectionStatus.tone == .warn)
        #expect(model.protectionStatus.action == .camera)
        #expect(model.appStatus.detail.contains("Touch ID"))
    }
    @Test func missingAccessibilityDoesNotDisableAppLock() throws {
        let model = try sample("accessibility-denied")
        #expect(model.lockStatus.tone == .warn)
        #expect(model.lockStatus.action == .lockScreen)
        #expect(model.appStatus.label == "Active")
        #expect(model.protectionStatus.tone == .warn)
    }
    @Test func missingAndRejectedPasswordsCannotReportLockScreenReady() throws {
        for scenario in ["password-missing", "password-rejected"] {
            let model = try sample(scenario)
            #expect(model.lockStatus.tone == .warn)
            #expect(model.protectionStatus.action == .lockScreen)
            #expect(model.appStatus.label == "Active")
        }
    }
    @Test func emptyAppSelectionOffersDirectPicker() throws {
        let model = try sample("empty-apps")
        #expect(model.protectionStatus.tone == .warn)
        #expect(model.protectionStatus.action == .addApp)
        #expect(model.lockStatus.label == "Ready")
    }
    @Test func appOnlyWithoutFaceOffersSetupAndKeepsSystemFallback() throws {
        let model = try sample("apps-only")
        #expect(model.lockStatus.label == "Off")
        #expect(model.protectionStatus.action == .setup)
        #expect(model.appStatus.detail.contains("Touch ID or your Mac password is available"))
    }
    @Test func engineFailureDoesNotClaimReady() throws {
        let model = try sample("engine-error")
        #expect(model.protectionStatus.tone == .warn)
        #expect(model.lockStatus.label != "Ready")
        #expect(model.protectionStatus.action == .face)
    }
    @Test func replacingFaceDoesNotClaimReadyWhileEngineIsStopped() throws {
        let model = try sample()
        model.beginFaceSetup()
        defer { model.endFaceSetup() }
        #expect(model.protectionStatus.title == "Face setup is in progress.")
        #expect(model.lockStatus.label != "Ready")
        #expect(model.appStatus.detail.contains("Touch ID"))
    }
    @Test func appOnlySetupSkipsLockScreenRequirements() throws {
        let flow = SetupFlow(model: try sample(), startAt: .welcome)
        flow.plan = .apps
        #expect(flow.activeSteps == [.welcome, .camera, .enroll, .test, .apps, .done])
        #expect(!flow.activeSteps.contains(.password))
        #expect(!flow.activeSteps.contains(.accessibility))
    }
    @Test func lockOnlySetupDoesNotAskForApps() throws {
        let flow = SetupFlow(model: try sample(), startAt: .welcome)
        flow.plan = .lock
        #expect(flow.activeSteps == [.welcome, .camera, .enroll, .test, .accessibility, .password, .done])
    }
    @Test func combinedSetupIncludesBothRequirementPaths() throws {
        let flow = SetupFlow(model: try sample(), startAt: .welcome)
        #expect(flow.activeSteps == SetupFlow.Step.allCases)
    }
    @Test func standaloneTestAndReplacementHaveTheirOwnRoutes() throws {
        let model = try sample()
        #expect(SetupFlow(model: model, startAt: .test).activeSteps == [.test])
        #expect(SetupFlow(model: model, startAt: .enroll).activeSteps == [.enroll, .test, .done])
    }
    @Test func backNavigationPreservesSelectedPlan() throws {
        let flow = SetupFlow(model: try sample(), startAt: .welcome)
        flow.plan = .apps
        flow.advance()
        #expect(flow.step == .camera)
        #expect(flow.canGoBack)
        flow.back()
        #expect(flow.step == .welcome)
        #expect(flow.plan == .apps)
    }
    @Test func unavailableModelsGiveActionableFeedback() throws {
        let flow = SetupFlow(model: try sample("no-face"), startAt: .enroll)
        flow.startEnrollment()
        #expect(!flow.enrolling)
        #expect(!flow.enrollHint.isEmpty)
        flow.runTest()
        #expect(!flow.testing)
        #expect(flow.testMessage != nil)
    }
    @Test func allReadinessCombinationsRespectProtectionInvariants() throws {
        let flags = ["lock-off", "apps-off", "no-face", "paused", "camera-denied", "accessibility-denied", "password-missing", "password-rejected", "empty-apps", "engine-error", "face-setup"]
        for mask in 0..<(1 << flags.count) {
            let scenario = flags.enumerated().compactMap { (index, name) in mask & (1 << index) == 0 ? nil : name }.joined(separator: "+")
            let model = try sample(scenario)
            let faceReady = model.setupComplete && model.cameraAuthorized && !model.paused && !model.busy && model.engineError == nil
            if model.lockStatus.label == "Ready" {
                #expect(model.lockScreenEnabled && faceReady && model.accessibilityTrusted && model.hasSavedPassword && !model.lockScreenNeedsPassword, "False Lock Screen readiness: \(scenario)")
            }
            if model.appStatus.label == "Active" {
                #expect(model.appLockEnabled && !model.appLockApps.isEmpty && faceReady, "False App Lock readiness: \(scenario)")
            }
            if model.protectionStatus.label == "Ready" {
                #expect(model.lockScreenEnabled || model.appLockEnabled, "False overall readiness: \(scenario)")
                #expect(!model.lockScreenEnabled || model.lockStatus.label == "Ready", "Lock Screen issue hidden: \(scenario)")
                #expect(!model.appLockEnabled || model.appStatus.label == "Active", "App Lock issue hidden: \(scenario)")
            }
            if !model.lockScreenEnabled && !model.appLockEnabled {
                #expect(model.protectionStatus.label == "Off", "Disabled protection misreported: \(scenario)")
            }
        }
    }

}
