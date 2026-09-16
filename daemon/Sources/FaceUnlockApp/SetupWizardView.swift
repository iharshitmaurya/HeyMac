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
            Image(systemName: "faceid").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Unlock sudo in Terminal and your lock screen by looking at the camera.")
            Label("Your face stays on this Mac, stored encrypted as numbers — not photos.", systemImage: "lock.shield")
            Label("Your password always keeps working. Face unlock is only a shortcut.", systemImage: "key")
            Label("The camera runs only while a check is happening.", systemImage: "video")
            Button("Get Started") { flow.advance() }.keyboardShortcut(.defaultAction)
        }
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FaceUnlock needs the camera to recognize you.")
            if flow.cameraAuthorized {
                Label("Camera access granted.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Continue") { flow.advance() }.keyboardShortcut(.defaultAction)
            } else if flow.cameraDenied {
                Label("Camera access was denied.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Turn it on in System Settings, then come back to this window.")
                HStack {
                    Button("Open System Settings") { flow.model.openSystemSettings(anchor: "Privacy_Camera") }
                    Button("Check Again") { flow.refreshCameraStatus() }
                }
            } else {
                Button("Allow Camera Access") { flow.requestCamera() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var enroll: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Look straight at the camera in good, even light.")
            preview
            if flow.enrolling {
                ProgressView(value: Double(flow.samplesCaptured), total: Double(flow.sampleTarget)) {
                    Text("Captured \(flow.samplesCaptured) of \(flow.sampleTarget)")
                }
            }
            if !flow.enrollHint.isEmpty { Text(flow.enrollHint).foregroundStyle(.secondary) }
            HStack {
                Button(flow.enrolling ? "Enrolling…" : "Start Enrolling") { flow.startEnrollment() }
                    .disabled(flow.enrolling)
                    .keyboardShortcut(.defaultAction)
                if flow.enrollFinished { Button("Continue") { flow.advance() } }
            }
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let's check that FaceUnlock recognizes you.")
            preview
            if flow.testing { ProgressView() }
            if let message = flow.testMessage {
                Label(message, systemImage: flow.testPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(flow.testPassed ? .green : .orange)
            }
            HStack {
                Button(flow.testing ? "Checking…" : "Test Now") { flow.runTest() }
                    .disabled(flow.testing)
                    .keyboardShortcut(.defaultAction)
                if flow.model.setupComplete {
                    Button("Close") { flow.close() }
                } else {
                    Button("Continue") { flow.advance() }.disabled(!flow.testPassed)
                }
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Unlock sudo with my face", isOn: Binding(
                    get: { flow.model.sudoEnabled }, set: { flow.model.setSudoEnabled($0) }
                )).disabled(flow.model.busy)
                Text("Adds face unlock to sudo in Terminal. macOS asks for your admin password once to install it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Unlock the lock screen with my face").bold()
                Text("FaceUnlock types your login password for you when it recognizes your face. It needs your password stored, encrypted, on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Login password", text: Binding(get: { flow.password }, set: { flow.password = $0 }))
                SecureField("Confirm password", text: Binding(get: { flow.passwordConfirm }, set: { flow.passwordConfirm = $0 }))
                Button("Save Password") { flow.saveLoginPassword() }
                if let message = flow.passwordMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                if flow.model.lockScreenEnabled {
                    if flow.model.accessibilityTrusted {
                        Label("Accessibility permission granted.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Needs Accessibility permission to type the password.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Grant Accessibility Permission") { flow.model.requestAccessibility() }
                    }
                }
            }

            Button("Continue") { flow.advance() }.keyboardShortcut(.defaultAction)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("FaceUnlock is ready.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Look for the face icon in the menu bar. From there you can pause it, test it, or change settings.")
            if flow.model.sudoEnabled {
                Text("Try it: open Terminal and run `sudo -k; sudo whoami` while looking at the camera.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Done") { flow.finish() }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.85))
            if let image = flow.preview {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(x: -1, y: 1)  // mirror, so moving left looks left
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Camera off").foregroundStyle(.secondary)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }
}
