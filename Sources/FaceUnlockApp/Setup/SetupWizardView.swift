import SwiftUI
import FaceUnlockEngine

/// Palette of the wizard design (light / dark).
private enum WZ {
    static let win = Color(light: 0xF5F5F7, dark: 0x1E1E20)
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let ctl = Color(light: 0xFFFFFF, dark: 0x3A3A3E)
    static let neu = Color(light: 0xE8E8ED, dark: 0x3A3A3E)
    static let text2 = Color(light: 0x5F5F66, dark: 0xA9A9B1)
    static let accent = Color(light: 0x0071E3, dark: 0x0A6FDC)
    static let accentPressed = Color(light: 0x0857AD, dark: 0x0B5FBF)
    static let accentTint = Color(light: 0xE4EFFC, dark: 0x1B2E48)
    static let accentText = Color(light: 0x0062C9, dark: 0x62AEFF)
    static let good = Color(light: 0x17692D, dark: 0x5FD47F)
    static let goodBg = Color(light: 0xE1F3E6, dark: 0x1F3A29)
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

    private static let stepCount = SetupFlow.Step.allCases.count

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
                               alignment: flow.step == .features ? .top : .center)
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
        case .features: features
        case .done: done
        }
    }

    // MARK: - Frame

    private var header: some View {
        let index = flow.step.rawValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<Self.stepCount, id: \.self) { i in
                    Capsule().fill(i <= index ? WZ.accent : WZ.track)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(index + 1) of \(Self.stepCount) · \(flow.title)")
                .font(.system(size: 11)).foregroundStyle(WZ.text2).lineLimit(1)
        }
        .padding(.horizontal, 48)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1) of \(Self.stepCount): \(flow.title)")
    }

    /// Back on the left; secondary and primary actions on the right. The primary never moves.
    private var footer: some View {
        HStack(spacing: 12) {
            if flow.canGoBack {
                Button("Back") { flow.back() }.buttonStyle(WizardButtonStyle(kind: .secondary))
            }
            Spacer(minLength: 12)
            footerButtons
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
                if flow.model.setupComplete { secondary("Test Again") { flow.runTest() } }
                primary(flow.model.setupComplete ? "Done" : "Continue") {
                    flow.model.setupComplete ? flow.close() : flow.advance()
                }
            } else {
                secondary("Re-enroll") { flow.restartEnrollment() }
                primary("Try Again") { flow.runTest() }
            }
        case .features:
            primary("Continue") { flow.advance() }
        case .done:
            primary("Done") { flow.finish() }
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
        VStack(spacing: 8) {
            Image(systemName: "faceid")
                .font(.system(size: 44, weight: .regular)).foregroundStyle(WZ.accent)
                .frame(width: 88, height: 88)
                .background(WZ.logoTile, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .accessibilityHidden(true)
            h1("Welcome to Hey Mac", size: 28).padding(.top, 8)
            bodyText("Unlock your lock screen and the apps you choose, just by looking at your Mac.")
            HStack(alignment: .top, spacing: 16) {
                feature("checkmark.shield", "Stays on your Mac", "Nothing is uploaded.")
                feature("photo", "No photos kept", "Only a small fingerprint.")
                feature("bolt.fill", "Quick to set up", "About a minute.")
            }
            .frame(maxWidth: 560).padding(.top, 24)
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
            Text("Enroll your face").font(.system(size: 17, weight: .semibold))
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
        if flow.enrollFinished { return "Your face is saved on this Mac." }
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
            Text("Check that it recognizes you").font(.system(size: 17, weight: .semibold))
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
        return flow.testPassed ? "It’s you!" : "We couldn’t match your face."
    }

    private var testSubline: String {
        if flow.testing { return "Look at the camera." }
        if flow.testMessage == nil { return "Look at the camera, then press Test Now." }
        return flow.testPassed
            ? "Hey Mac is working."
            : "Try facing the camera in better light. If it keeps happening, enroll again."
    }

    private var testColor: Color {
        if flow.testing || flow.testMessage == nil { return .primary }
        return flow.testPassed ? WZ.good : WZ.bad
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Turn on what you want").font(.system(size: 22, weight: .semibold))
                Text("You can change any of this later in Settings.")
                    .font(.system(size: 11)).foregroundStyle(WZ.text2)
            }
            VStack(spacing: 0) {
                lockScreenRow
                Rectangle().fill(WZ.sep).frame(height: 1)
                accessibilityRow
            }
            .background(WZ.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WZ.sep, lineWidth: 1))
        }
    }

    private var lockScreenOn: Bool { flow.model.lockScreenEnabled || flow.lockScreenWanted }

    private var lockScreenRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                tile("lock.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock the lock screen").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(flow.passwordMessage ?? "Needs your login password. It stays on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(passwordMessageColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("Unlock the lock screen", isOn: Binding(
                    get: { lockScreenOn },
                    set: { flow.setLockScreenWanted($0) }
                ))
                .toggleStyle(.switch).labelsHidden().tint(WZ.accent)
            }
            .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 48)

            if flow.lockScreenWanted && !flow.model.lockScreenEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        passwordField("Login password", text: Binding(get: { flow.password }, set: { flow.password = $0 }))
                        passwordField("Confirm password", text: Binding(get: { flow.passwordConfirm }, set: { flow.passwordConfirm = $0 }))
                    }
                    HStack {
                        secondary("Save Password") { flow.saveLoginPassword() }
                            .disabled(flow.password.isEmpty || flow.passwordConfirm.isEmpty)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    private var passwordMessageColor: Color {
        guard let message = flow.passwordMessage else { return WZ.text2 }
        return message == "Password saved." ? WZ.good : WZ.warn
    }

    private func passwordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(WZ.text2)
            SecureField("", text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 8).frame(height: 28)
                .background(WZ.ctl, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityRow: some View {
        HStack(spacing: 12) {
            tile("keyboard")
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("Lets Hey Mac press keys on the lock screen.")
                    .font(.system(size: 11)).foregroundStyle(WZ.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if flow.model.accessibilityTrusted {
                chip("Allowed", icon: "checkmark", fg: WZ.good, bg: WZ.goodBg)
            } else {
                chip("Needs permission", icon: "exclamationmark.triangle.fill", fg: WZ.warn, bg: WZ.warnBg)
                secondary("Open Settings") { flow.model.requestAccessibility() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 48)
    }

    private var done: some View {
        VStack(spacing: 12) {
            circleIcon("checkmark", tint: WZ.good, bg: WZ.goodBg)
            h1("You’re set")
            bodyText("Look at your Mac when you wake the screen. Add apps to lock any time in Settings.")
            HStack(alignment: .top, spacing: 12) {
                feature("lock.fill", "Lock screen", "Wake your Mac and look.")
                feature("lock.app.dashed", "App Lock", "Add apps in Settings.")
            }
            .frame(maxWidth: 420).padding(.top, 16)
        }
    }
}
