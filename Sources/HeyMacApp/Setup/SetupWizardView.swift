import AppKit
import SwiftUI
import HeyMacEngine

/// Palette of the wizard design (light / dark).
private enum WZ {
    static let win = Color(light: 0xF5F5F7, dark: 0x1E1E20)
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let ctl = Color(light: 0xFFFFFF, dark: 0x3A3A3E)
    static let text2 = Color(light: 0x5F5F66, dark: 0xA9A9B1)
    static let accent = Theme.accent
    static let accentPressed = Color(light: 0x0857AD, dark: 0x0B5FBF)
    static let accentTint = Color(light: 0xE4EFFC, dark: 0x1B2E48)
    static let accentText = Color(light: 0x0062C9, dark: 0x62AEFF)
    static let good = Theme.goodText
    static let goodBg = Theme.good.opacity(0.12)
    static let warn = Color(light: 0x8F5200, dark: 0xFFB340)
    static let warnBg = Color(light: 0xFDEFD6, dark: 0x40311A)
    static let bad = Color(light: 0xB92E26, dark: 0xFF7A70)
    static let badFill = Color(light: 0xC0322A, dark: 0xD23B31)
    static let disc = Color(light: 0x2A2D33, dark: 0x2A2D33)
    static let logoTile = Color(light: 0xF6F8FC, dark: 0x2A2D33)
    static let sep = Color.primary.opacity(0.12)
    static let track = Color.primary.opacity(0.2)
}

private struct WizardButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        WizardBody(configuration: configuration, kind: kind)
    }

    private struct WizardBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: kind == .primary ? 96 : 0, minHeight: 32)
                .foregroundStyle(kind == .primary ? Color.white : Color.primary)
                .background(fill, in: shape)
                .overlay(shape.stroke(kind == .secondary ? Color.primary.opacity(0.2) : .clear, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary: return pressed ? WZ.accentPressed : WZ.accent
            case .secondary: return pressed ? Color.primary.opacity(0.12) : WZ.ctl
            }
        }
    }
}

struct SetupWizardView: View {
    let flow: SetupFlow

    private var stepCount: Int { flow.activeSteps.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ScrollView {
                    content
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height,
                               alignment: flow.step == .apps ? .top : .center)
                }
            }
            Rectangle().fill(WZ.sep).frame(height: 1)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WZ.win)
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome: welcome
        case .camera: camera
        case .enroll: enroll
        case .test: test
        case .accessibility: accessibility
        case .password: passwordSetup
        case .apps: appSelection
        case .done: done
        }
    }

    // MARK: - Frame

    private var header: some View {
        let index = flow.stepIndex
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule().fill(i <= index ? WZ.accent : WZ.track)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(index + 1) of \(stepCount) · \(flow.title)")
                .font(.system(size: 11)).foregroundStyle(WZ.text2).lineLimit(1)
        }
        .padding(.horizontal, 48)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1) of \(stepCount): \(flow.title)")
    }

    /// Back on the left; secondary and primary actions on the right. The primary never moves.
    private var footer: some View {
        HStack(spacing: 12) {
            if flow.canGoBack {
                Button("Back") { flow.back() }.buttonStyle(WizardButtonStyle(kind: .secondary))
            }
            if flow.startStep == .welcome && ![.welcome, .done].contains(flow.step) && !flow.working {
                Button([.camera, .enroll, .test].contains(flow.step) ? "Finish Setup Later" : "Skip for Now") {
                    if [.camera, .enroll, .test].contains(flow.step) { flow.finishLater() } else { flow.advance() }
                }.buttonStyle(.plain).foregroundStyle(WZ.accentText)
            }
            Spacer(minLength: 12)
            if flow.working {
                secondary("Cancel") { flow.cancelWork() }
            } else { footerButtons }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(minHeight: 66)
        .background(WZ.win)
    }

    @ViewBuilder private var footerButtons: some View {
        switch flow.step {
        case .welcome:
            primary("Continue") { flow.advance() }
        case .camera:
            if flow.cameraAuthorized {
                primary("Continue") { flow.advance() }
            } else if flow.cameraDenied {
                secondary("Check Again") { flow.refreshCameraStatus() }
                primary("Open System Settings") { flow.model.openSystemSettings(anchor: "Privacy_Camera") }
            } else {
                primary("Allow Camera") { flow.requestCamera() }
            }
        case .enroll:
            if flow.enrollFinished {
                primary("Continue") { flow.advance() }
            } else {
                primary(flow.enrolling ? "Enrolling…" : "Start Enrolling") { flow.startEnrollment() }
                    .disabled(flow.enrolling)
            }
        case .test:
            if flow.testing {
                primary("Checking…") {}.disabled(true)
            } else if flow.testMessage == nil {
                primary("Test Now") { flow.runTest() }
            } else if flow.testPassed {
                if flow.standaloneTest { secondary("Test Again") { flow.runTest() } }
                primary(flow.standaloneTest ? "Done" : "Continue") {
                    flow.standaloneTest ? flow.close() : flow.advance()
                }
            } else {
                secondary("Re-enroll") { flow.restartEnrollment() }
                primary("Try Again") { flow.runTest() }
            }
        case .accessibility:
            if flow.model.accessibilityTrusted { primary("Continue") { flow.advance() } }
            else { primary("Open System Settings") { flow.model.requestAccessibility() } }
        case .password:
            if flow.model.hasSavedPassword && !flow.model.lockScreenNeedsPassword {
                primary("Continue") { flow.advance() }
            } else {
                primary("Save Password and Continue") { flow.saveLoginPassword() }
                    .disabled(flow.password.isEmpty || flow.passwordConfirm.isEmpty)
            }
        case .apps:
            primary("Continue") { flow.advance() }
        case .done:
            primary("Open Settings") { flow.finish() }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(WizardButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(WizardButtonStyle(kind: .secondary))
    }

    // MARK: - Shared pieces

    private func h1(_ text: String, size: CGFloat = 22) -> some View {
        Text(text).font(.system(size: size, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(WZ.text2)
            .lineSpacing(4).multilineTextAlignment(.center)
            .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
    }

    private func circleIcon(_ symbol: String, tint: Color, bg: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .regular)).foregroundStyle(tint)
            .frame(width: 72, height: 72).background(bg, in: Circle())
            .accessibilityHidden(true)
    }

    private func tile(_ symbol: String, size: CGFloat = 28) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(WZ.accentText)
            .frame(width: size, height: size)
            .background(WZ.accentTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private func chip(_ text: String, icon: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).frame(height: 20)
        .background(bg, in: Capsule())
    }

    private func feature(_ symbol: String, _ title: String, _ caption: String) -> some View {
        VStack(spacing: 6) {
            tile(symbol, size: 36)
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(caption).font(.system(size: 11)).foregroundStyle(WZ.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(good: Bool) -> some View {
        Image(systemName: good ? "checkmark" : "xmark")
            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(good ? WZ.good : WZ.badFill, in: Circle())
            .overlay(Circle().stroke(WZ.win, lineWidth: 3))
    }

    /// Always on the dark disc, so fixed light text.
    private var cameraOffLabel: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash").font(.system(size: 22)).accessibilityHidden(true)
            Text("Camera off").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(0.85))
    }

    private func preview(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(WZ.disc)
            if let image = flow.preview {
                Image(decorative: image, scale: 1)
                    .resizable().aspectRatio(contentMode: .fill)
                    .scaleEffect(x: -1, y: 1) // mirror, so moving left looks left
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                cameraOffLabel
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            h1("How would you like to use Hey Mac?", size: 27)
            bodyText("Choose a starting point. You can enable the other feature later.")
            VStack(spacing: 8) {
                ForEach(SetupFlow.Plan.allCases, id: \.self) { plan in
                    Button { flow.plan = plan } label: {
                        HStack(spacing: 12) {
                            Image(systemName: flow.plan == plan ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(flow.plan == plan ? Theme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.rawValue).font(Typography.rowTitle)
                                CaptionText(plan.detail)
                            }
                            Spacer()
                        }.padding(16).background(WZ.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(flow.plan == plan ? Theme.accent : WZ.sep, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(flow.plan == plan ? .isSelected : [])
                }
            }.frame(maxWidth: 480)
        }
    }

    private var camera: some View {
        VStack(spacing: 12) {
            if flow.cameraAuthorized {
                circleIcon("checkmark", tint: WZ.good, bg: WZ.goodBg)
                h1("Camera access allowed")
                bodyText("Hey Mac can see you when you unlock. Photos are never saved, and nothing leaves your Mac.")
            } else if flow.cameraDenied {
                circleIcon("exclamationmark.triangle", tint: WZ.warn, bg: WZ.warnBg)
                h1("Camera access is off")
                bodyText("Hey Mac can’t see you without it. Turn it on in System Settings, under Privacy & Security, then Camera.")
                chip("Permission denied", icon: "exclamationmark.triangle.fill", fg: WZ.warn, bg: WZ.warnBg)
            } else {
                circleIcon("camera", tint: WZ.accentText, bg: WZ.accentTint)
                h1("Allow camera access")
                bodyText("Hey Mac uses the camera only to see your face when you unlock. Photos are never saved, and nothing leaves your Mac.")
            }
        }
    }

    private var enroll: some View {
        VStack(spacing: 8) {
            Text("Set up face recognition").font(.system(size: 17, weight: .semibold))
            enrollRing
            Text(enrollHeadline).font(.system(size: 13, weight: .medium))
                .foregroundStyle(hintColor).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(enrollSubline).font(.system(size: 11)).foregroundStyle(WZ.text2)
                .multilineTextAlignment(.center)
        }
    }

    private var enrollHeadline: String {
        if flow.enrollFinished { return "All set. That’s all \(flow.sampleTarget) samples." }
        return flow.enrollHint.isEmpty ? "Hold still and look straight at the camera." : flow.enrollHint
    }

    private var enrollSubline: String {
        if flow.enrollFinished { return "Test recognition to save your face setup. Your existing data stays unchanged until the test succeeds." }
        if flow.enrolling { return "Sample \(min(flow.samplesCaptured + 1, flow.sampleTarget)) of \(flow.sampleTarget). Turn your head slowly." }
        return "We’ll take \(flow.sampleTarget) quick samples in good, even light."
    }

    private var hintColor: Color {
        switch flow.enrollHintTone {
        case .neutral: return .primary
        case .good: return WZ.good
        case .warn: return WZ.warn
        }
    }

    /// The live preview inside a progress ring with one dot per sample.
    private var enrollRing: some View {
        let progress = flow.sampleTarget > 0 ? Double(flow.samplesCaptured) / Double(flow.sampleTarget) : 0
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4).frame(width: 246, height: 246)
            Circle().trim(from: 0, to: progress)
                .stroke(WZ.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 246, height: 246).rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: flow.samplesCaptured)
            ForEach(0..<max(flow.sampleTarget, 1), id: \.self) { i in
                let angle = Double(i) / Double(max(flow.sampleTarget, 1)) * 2 * .pi
                Circle().fill(i < flow.samplesCaptured ? WZ.accent : WZ.track)
                    .frame(width: 6, height: 6)
                    .offset(x: 123 * sin(angle), y: -123 * cos(angle))
            }
            preview(diameter: 220)
            if flow.enrollFinished {
                badge(good: true).offset(x: 86, y: 86).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 264, height: 264)
        .animation(.easeOut(duration: 0.3), value: flow.enrollFinished)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enrollment progress")
        .accessibilityValue("\(flow.samplesCaptured) of \(flow.sampleTarget) samples")
    }

    private var test: some View {
        let done = !flow.testing && flow.testMessage != nil
        return VStack(spacing: 8) {
            Text("Test Face Recognition").font(.system(size: 17, weight: .semibold))
            ZStack {
                Circle().stroke(ringColor, lineWidth: 4).frame(width: 186, height: 186)
                preview(diameter: 170)
                if done { badge(good: flow.testPassed).offset(x: 66, y: 66) }
            }
            .frame(width: 190, height: 190)
            .animation(.easeOut(duration: 0.3), value: flow.testPassed)
            Text(testHeadline).font(.system(size: 13, weight: .medium))
                .foregroundStyle(testColor).multilineTextAlignment(.center)
            Text(testSubline).font(.system(size: 11)).foregroundStyle(WZ.text2)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ringColor: Color {
        if flow.testing || flow.testMessage == nil { return WZ.accent.opacity(0.35) }
        return flow.testPassed ? WZ.good : WZ.badFill
    }

    private var testHeadline: String {
        if flow.testing { return "Looking for your face…" }
        if flow.testMessage == nil { return "Ready when you are." }
        return flow.testPassed ? "Recognized." : "Face recognition needs attention."
    }

    private var testSubline: String {
        if flow.testing { return "Look at the camera." }
        if flow.testMessage == nil { return "Look at the camera, then press Test Now." }
        return flow.testMessage ?? "Try face recognition again."
    }

    private var testColor: Color {
        if flow.testing || flow.testMessage == nil { return .primary }
        return flow.testPassed ? WZ.good : WZ.bad
    }

    private var accessibility: some View {
        VStack(spacing: 16) {
            circleIcon("keyboard", tint: WZ.accentText, bg: WZ.accentTint)
            h1("Allow Accessibility access.")
            bodyText("Accessibility lets Hey Mac enter your saved Mac login password after recognizing you. App Lock doesn’t need this permission.")
            if flow.model.accessibilityTrusted { StatusChip(text: "Allowed", tone: .good) }
            else { bodyText("Enable Hey Mac in System Settings → Privacy & Security → Accessibility, then return here.") }
        }
    }

    private var passwordSetup: some View {
        VStack(spacing: 16) {
            circleIcon("lock", tint: WZ.accentText, bg: WZ.accentTint)
            h1("Finish Lock Screen Setup")
            bodyText("Hey Mac enters your saved Mac login password after recognizing you. Verify your identity before saving it. Your Mac password and Touch ID continue to work as usual.")
            if flow.model.hasSavedPassword && !flow.model.lockScreenNeedsPassword {
                StatusChip(text: "Password saved", tone: .good)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    passwordField("Mac login password", text: Binding(get: { flow.password }, set: { flow.password = $0 }))
                    passwordField("Confirm password", text: Binding(get: { flow.passwordConfirm }, set: { flow.passwordConfirm = $0 }))
                }.frame(maxWidth: 380)
            }
            if let message = flow.passwordMessage { bodyText(message) }
        }
    }

    private func passwordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typography.caption).foregroundStyle(WZ.text2)
            SecureField(label, text: text).labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(label)
        }
    }

    private var appSelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Apps to Protect").font(.system(size: 27, weight: .semibold))
            CaptionText("Select one or more apps. You can set a relock time for each app in Settings.")
            TextField("Find an app", text: Binding(get: { flow.appSearch }, set: { flow.appSearch = $0 })).textFieldStyle(.roundedBorder)
            let results = flow.availableApps.filter { flow.appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(flow.appSearch) }
            if results.isEmpty {
                CaptionText("No apps found.")
                Button("Clear Search") { flow.appSearch = "" }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            ForEach(results) { app in
                let selected = flow.model.appLockApps.contains { $0.bundleID == app.bundleID }
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
                    Text(app.name).font(Typography.body).lineLimit(2)
                    Spacer()
                    Button(selected ? "Deselect" : "Select") {
                        if selected { flow.model.removeLockedApp(app.bundleID) } else { flow.model.addLockedApp(app) }
                    }
                        .buttonStyle(WizardButtonStyle(kind: .secondary))
                        .accessibilityLabel(selected ? "\(app.name) selected" : "Select \(app.name)")
                }.padding(12).background(WZ.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func readinessRow(_ title: String, _ value: String, ready: Bool) -> some View {
        HStack {
            Text(title).font(Typography.body)
            Spacer()
            StatusChip(text: value, tone: ready ? .good : .warn)
        }.padding(12)
    }

    private var done: some View {
        let lockReady = flow.model.setupComplete && flow.model.cameraAuthorized && flow.model.accessibilityTrusted && flow.model.hasSavedPassword && !flow.model.lockScreenNeedsPassword
        return VStack(spacing: 16) {
            circleIcon("checklist", tint: WZ.accentText, bg: WZ.accentTint)
            h1("Here’s what’s ready.", size: 27)
            bodyText("Review your setup below. Finish any remaining steps in Settings.")
            VStack(spacing: 0) {
                readinessRow("Face setup", flow.model.setupComplete ? "Ready" : "Not set up", ready: flow.model.setupComplete)
                Divider()
                readinessRow("Recognition check", flow.testPassed ? "Tested" : "Not tested in this setup", ready: flow.testPassed)
                if flow.startStep == .welcome && flow.wantsLockScreen {
                    Divider()
                    readinessRow("Lock Screen", lockReady ? "Ready" : "Setup incomplete", ready: lockReady)
                }
                if flow.startStep == .welcome && flow.wantsAppLock {
                    Divider()
                    readinessRow("App Lock", flow.model.appLockApps.isEmpty ? "No apps selected" : "\(flow.model.appLockApps.count) apps selected", ready: !flow.model.appLockApps.isEmpty)
                }
            }.background(WZ.card, in: RoundedRectangle(cornerRadius: 12))
            bodyText(flow.startStep == .welcome ? "Ready features turn on when you open Settings. App Lock can also use Touch ID or your Mac password." : "Your updated face setup is saved. Your protection settings stay as you chose them.")
        }
    }
}
