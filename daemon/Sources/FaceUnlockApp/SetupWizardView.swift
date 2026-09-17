import SwiftUI
import FaceUnlockEngine

struct SetupWizardView: View {
    let flow: SetupFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(flow.title).font(.title2).bold()

            switch flow.step {
            case .welcome: welcome
            case .camera: camera
            case .enroll: enroll
            case .test: test
            case .features: features
            case .done: done
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 560, alignment: .topLeading)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "faceid").font(.system(size: 52)).foregroundStyle(Theme.accent)
            Text("Unlock sudo in Terminal and your lock screen by looking at the camera.")
            Label("Your face stays on this Mac, stored encrypted as numbers — not photos.", systemImage: "lock.shield")
            Label("Your password always keeps working. Face unlock is only a shortcut.", systemImage: "key")
            Label("The camera runs only while a check is happening.", systemImage: "video")
            Button("Get Started") { flow.advance() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FaceUnlock needs the camera to recognize you.")
            if flow.cameraAuthorized {
                Label("Camera access granted.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Button("Continue") { flow.advance() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            } else if flow.cameraDenied {
                Label("Camera access was denied.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                Text("Turn it on in System Settings, then come back to this window.")
                HStack(spacing: 10) {
                    Button("Open System Settings") { flow.model.openSystemSettings(anchor: "Privacy_Camera") }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                    Button("Check Again") { flow.refreshCameraStatus() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.top, 6)
            } else {
                Button("Allow Camera Access") { flow.requestCamera() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
        }
    }

    private var enroll: some View {
        VStack(spacing: 18) {
            Text("Look straight at the camera in good, even light.")
                .frame(maxWidth: .infinity, alignment: .leading)
            enrollPreview
            sampleDots
            Text(flow.enrollHint.isEmpty ? " " : flow.enrollHint)
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                .frame(minHeight: 16)
            HStack(spacing: 10) {
                Button(flow.enrolling ? "Enrolling…" : "Start Enrolling") { flow.startEnrollment() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(flow.enrolling)
                    .keyboardShortcut(.defaultAction)
                if flow.enrollFinished {
                    Button("Continue") { flow.advance() }.buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Camera off").font(.system(size: 12)).foregroundStyle(.secondary)
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
        VStack(spacing: 18) {
            Text("Let's check that FaceUnlock recognizes you.")
                .frame(maxWidth: .infinity, alignment: .leading)
            testPreview
            HStack(spacing: 10) {
                MatchFeedbackView(state: matchState)
                Text(matchCaption).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            HStack(spacing: 10) {
                Button(flow.testing ? "Checking…" : "Test Now") { flow.runTest() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(flow.testing)
                    .keyboardShortcut(.defaultAction)
                if flow.model.setupComplete {
                    Button("Close") { flow.close() }.buttonStyle(PillButtonStyle(kind: .secondary))
                } else {
                    Button("Continue") { flow.advance() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                        .disabled(!flow.testPassed)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Circular, centered — matches the enrollment preview's framing so the two screens
    /// read as the same "camera moment," not two different UI styles.
    private var matchState: MatchState {
        if flow.testing { return .idle }
        if flow.testMessage != nil { return flow.testPassed ? .success : .fail }
        return .idle
    }

    private var matchCaption: String {
        if flow.testing { return "Scanning…" }
        return flow.testMessage ?? " "
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
                Text("Camera off").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6).frame(width: 236, height: 236)
        }
        .frame(width: 236, height: 236)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Unlock sudo with my face", isOn: Binding(
                    get: { flow.model.sudoEnabled }, set: { flow.model.setSudoEnabled($0) }
                )).tint(Theme.accent).disabled(flow.model.busy)
                Text("Adds face unlock to sudo in Terminal. macOS asks for your admin password once to install it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Unlock the lock screen with my face").bold()
                Text("FaceUnlock types your login password for you when it recognizes your face. It needs your password stored, encrypted, on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Login password", text: Binding(get: { flow.password }, set: { flow.password = $0 }))
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: Binding(get: { flow.passwordConfirm }, set: { flow.passwordConfirm = $0 }))
                    .textFieldStyle(.roundedBorder)
                Button("Save Password") { flow.saveLoginPassword() }.buttonStyle(PillButtonStyle(kind: .secondary))
                if let message = flow.passwordMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                if flow.model.lockScreenEnabled {
                    if flow.model.accessibilityTrusted {
                        Label("Accessibility permission granted.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    } else {
                        Label("Needs Accessibility permission to type the password.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warn)
                        Button("Grant Accessibility Permission") { flow.model.requestAccessibility() }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }

            Button("Continue") { flow.advance() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("FaceUnlock is ready.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.good)
            Text("Look for the face icon in the menu bar. From there you can pause it, test it, or change settings.")
            if flow.model.sudoEnabled {
                Text("Try it: open Terminal and run `sudo -k; sudo whoami` while looking at the camera.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Done") { flow.finish() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
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
