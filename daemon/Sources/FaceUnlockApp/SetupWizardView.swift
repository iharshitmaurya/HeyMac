import SwiftUI
import FaceUnlockEngine

struct SetupWizardView: View {
    let flow: SetupFlow

    private static let stepCount = SetupFlow.Step.allCases.count

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.lg)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Step \(index + 1) of \(Self.stepCount)")
                .font(Typography.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: Spacing.xs) {
                ForEach(0..<Self.stepCount, id: \.self) { i in
                    Capsule().fill(i <= index ? Theme.accent : Color.primary.opacity(0.14))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text(flow.title).font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1) of \(Self.stepCount): \(flow.title)")
    }

    /// Pinned action bar: Back leading, secondary then primary trailing — the primary never moves.
    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            if flow.canGoBack {
                Button("Back") { flow.back() }.buttonStyle(PillButtonStyle(kind: .secondary))
            }
            Spacer(minLength: Spacing.sm)
            footerButtons
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .frame(minHeight: 64)
    }

    @ViewBuilder private var footerButtons: some View {
        switch flow.step {
        case .welcome:
            primary("Get Started") { flow.advance() }
        case .camera:
            if flow.cameraAuthorized {
                primary("Continue") { flow.advance() }
            } else if flow.cameraDenied {
                secondary("Check Again") { flow.refreshCameraStatus() }
                primary("Open System Settings") { flow.model.openSystemSettings(anchor: "Privacy_Camera") }
            } else {
                primary("Allow Camera Access") { flow.requestCamera() }
            }
        case .enroll:
            if flow.enrollFinished {
                primary("Continue") { flow.advance() }
            } else {
                primary(flow.enrolling ? "Enrolling…" : "Start Enrolling") { flow.startEnrollment() }
                    .disabled(flow.enrolling)
            }
        case .test:
            if flow.model.setupComplete {
                secondary("Close") { flow.close() }
                primary(flow.testing ? "Checking…" : "Test Now") { flow.runTest() }.disabled(flow.testing)
            } else if flow.testPassed {
                secondary(flow.testing ? "Checking…" : "Test Again") { flow.runTest() }.disabled(flow.testing)
                primary("Continue") { flow.advance() }
            } else {
                primary(flow.testing ? "Checking…" : "Test Now") { flow.runTest() }.disabled(flow.testing)
            }
        case .features:
            primary("Continue") { flow.advance() }
        case .done:
            primary("Done") { flow.finish() }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(PillButtonStyle(kind: .secondary))
    }

    /// Status line: colored icon plus text in the adaptive text color, wrapping allowed.
    private func banner(_ text: String, icon: String, tone: StatusChip.Tone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: icon).foregroundStyle(tone.color).accessibilityHidden(true)
            Text(text).foregroundStyle(tone.textColor).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: icon).foregroundStyle(Theme.accentText)
                .frame(width: 22).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: "faceid").font(.system(size: 52)).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Unlock your Mac's lock screen by looking at the camera.")
            point("Your face stays on this Mac, stored encrypted as numbers — not photos.", icon: "lock.shield")
            point("Your password always keeps working. Face unlock is only a shortcut.", icon: "key")
            point("The camera runs only while a check is happening.", icon: "video")
        }
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("FaceUnlock needs the camera to recognize you.")
            if flow.cameraAuthorized {
                banner("Camera access granted.", icon: "checkmark.circle.fill", tone: .good)
            } else if flow.cameraDenied {
                banner("Camera access was denied.", icon: "exclamationmark.triangle.fill", tone: .warn)
                CaptionText("Turn it on in System Settings, then come back to this window.")
            }
        }
    }

    private var enroll: some View {
        VStack(spacing: Spacing.lg) {
            Text("Look straight at the camera in good, even light.")
                .frame(maxWidth: .infinity, alignment: .leading)
            enrollPreview
            sampleDots
            Text(flow.enrollHint)
                .font(.system(size: 13))
                .foregroundStyle(hintColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
        }
    }

    private var hintColor: Color {
        switch flow.enrollHintTone {
        case .neutral: return .secondary
        case .good: return Theme.goodText
        case .warn: return Theme.warnText
        }
    }

    /// The circular preview, ringed by one continuous progress arc that closes as live
    /// samples come in, ending in a checkmark that draws itself in
    /// pose-tracked tick ring (we don't guide head turns, just take 8 live samples), but
    /// the same idea of "progress you can see without reading a number."
    private var enrollPreview: some View {
        ZStack {
            Circle().fill(.black.opacity(0.85))
                .frame(width: 220, height: 220)

            if let image = flow.preview, !flow.enrollFinished {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(x: -1, y: 1) // mirror, so moving left looks left
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
            } else if !flow.enrollFinished {
                cameraOffLabel(nil)
            }

            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                .frame(width: 236, height: 236)
            Circle()
                .trim(from: 0, to: enrollProgress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 236, height: 236)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: flow.samplesCaptured)

            if flow.enrollFinished {
                ZStack {
                    Circle().fill(Theme.good.opacity(0.16)).frame(width: 74, height: 74)
                    CheckmarkShape()
                        .trim(from: 0, to: flow.enrollFinished ? 1 : 0)
                        .stroke(Theme.good, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .frame(width: 34, height: 34)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .animation(.easeOut(duration: 0.45), value: flow.enrollFinished)
            }
        }
        .frame(width: 236, height: 236)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enrollment progress")
        .accessibilityValue("\(flow.samplesCaptured) of \(flow.sampleTarget) samples")
    }

    private var enrollProgress: Double {
        flow.sampleTarget > 0 ? Double(flow.samplesCaptured) / Double(flow.sampleTarget) : 0
    }

    /// One dot per sample, filled as each one lands — discrete progress a pose-tracked
    /// ring doesn't need to show, since we're not confirming a head direction, just a count.
    private var sampleDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<flow.sampleTarget, id: \.self) { index in
                Circle()
                    .fill(index < flow.samplesCaptured ? Theme.accent : Color.primary.opacity(0.14))
                    .frame(width: 7, height: 7)
                    .scaleEffect(index == flow.samplesCaptured - 1 ? 1.4 : 1)
                    .animation(.spring(response: 0.32, dampingFraction: 0.55), value: flow.samplesCaptured)
            }
        }
    }

    private var test: some View {
        VStack(spacing: Spacing.lg) {
            Text("Look at the camera, then press Test Now.")
                .frame(maxWidth: .infinity, alignment: .leading)
            testPreview
            VStack(spacing: Spacing.sm) {
                MatchFeedbackView(state: matchState)
                Text(matchCaption)
                    .font(.system(size: 13)).foregroundStyle(matchColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
            }
        }
    }

    private var matchState: MatchState {
        if flow.testing { return .idle }
        if flow.testMessage != nil { return flow.testPassed ? .success : .fail }
        return .idle
    }

    private var matchCaption: String {
        if flow.testing { return "Scanning…" }
        return flow.testMessage ?? ""
    }

    private var matchColor: Color {
        if flow.testing || flow.testMessage == nil { return .secondary }
        return flow.testPassed ? Theme.goodText : Theme.badText
    }

    private var testPreview: some View {
        ZStack {
            Circle().fill(.black.opacity(0.85)).frame(width: 220, height: 220)
            if let image = flow.preview {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
            } else {
                cameraOffLabel("Press Test Now to start")
            }
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6).frame(width: 236, height: 236)
        }
        .frame(width: 236, height: 236)
    }

    /// Always on the black disc, so fixed light text — never `.secondary`, which is dark in light mode.
    private func cameraOffLabel(_ detail: String?) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "video.slash").font(.system(size: 22)).accessibilityHidden(true)
            Text("Camera off").font(.system(size: 13, weight: .semibold))
            if let detail { Text(detail).font(Typography.caption) }
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xl)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Unlock the lock screen with my face").bold()
                CaptionText("FaceUnlock types your login password for you when it recognizes your face. It needs your password stored, encrypted, on this Mac.")
                SecureField("Login password", text: Binding(get: { flow.password }, set: { flow.password = $0 }))
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: Binding(get: { flow.passwordConfirm }, set: { flow.passwordConfirm = $0 }))
                    .textFieldStyle(.roundedBorder)
                secondary("Save Password") { flow.saveLoginPassword() }
                    .disabled(flow.password.isEmpty || flow.passwordConfirm.isEmpty)
                if let message = flow.passwordMessage {
                    banner(message, icon: message == "Password saved." ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                           tone: message == "Password saved." ? .good : .warn)
                        .font(Typography.caption)
                }
                if flow.model.lockScreenEnabled {
                    if flow.model.accessibilityTrusted {
                        banner("Accessibility permission granted.", icon: "checkmark.circle.fill", tone: .good)
                    } else {
                        banner("Needs Accessibility permission to type the password.", icon: "exclamationmark.triangle.fill", tone: .warn)
                        secondary("Grant Accessibility Permission") { flow.model.requestAccessibility() }
                    }
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            banner("FaceUnlock is ready.", icon: "checkmark.seal.fill", tone: .good)
            Text("Look for the face icon in the menu bar. From there you can pause it or open Settings, where you can also test it, lock apps with App Lock, or set it up again.")
        }
    }

    /// A hand-drawn checkmark path, traced in via `.trim` rather than an SF Symbol —
    /// the enrollment ring closing into a check that draws itself is the payoff moment.
    private struct CheckmarkShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.52))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.78))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.2))
            return path
        }
    }

}
