<div align="center">

<img src="assets/logo.svg" width="90" alt="Animated Hey Mac Logo" style="margin-bottom: 20px; box-shadow: 0 10px 20px rgba(0,0,0,0.15); border-radius: 22px;"/>

# Hey Mac

**Your face is the password.**<br>
Unlock your Mac's lock screen and secure individual apps with a single look.

<br>

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=for-the-badge&logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Native-0071E3?style=for-the-badge&logo=apple&logoColor=white)
![Privacy](https://img.shields.io/badge/100%25-On--Device-34C759?style=for-the-badge&logo=shield&logoColor=white)
![Views](https://komarev.com/ghpvc/?username=iharshitmaurya&repo=HeyMac&label=Views&color=0071E3&style=for-the-badge)

</div>

<br>

---

## ✨ Features

Hey Mac bridges the gap between iOS-level convenience and macOS security, bringing native-feeling facial recognition to your desktop.

*   🔓 **Zero-Touch Unlock:** Wake your Mac, look at the screen, and you're immediately logged in. No keyboard required.
*   🛡️ **Application-Level Shielding:** Protect sensitive apps (Messages, Notes, Mail). Unauthorized viewers see a blurred interface until your identity is verified via Face, Touch ID, or password.
*   🎚️ **Customizable Privacy Levels:** Tailor how aggressive the locking behavior should be:
    * **Low Privacy:** Checks your face *only once* when the app starts. It stays unlocked until you close the app, without minimizing windows.
    * **Standard Privacy:** Checks your face based on the specific time limit you choose for that app (e.g., every 5 min, 15 min), without minimizing windows.
    * **High Privacy:** Maximum security. Authenticates and minimizes the app window on *every* window switch or focus loss.
*   🌫️ **Adaptive Privacy Blurs:** Choose your obfuscation level. Blur the entire display for maximum privacy, or strictly blur the locked application window to maintain workflow context.
*   🏝️ **Dynamic Notch Island:** A fluid, native-feeling UI drops down from the macOS notch, providing instant visual feedback during biometric scans.
*   🧑‍🚀 **Frictionless Onboarding:** A polished 6-step setup wizard guides you through camera permissions, facial enrollment, testing, and security preferences.

---

## 📦 Install (From Source)

Since this project requires accessing the macOS keychain and Face ID hardware, the most secure way to install it is to build it yourself from the source code.

1. **Clone the repository:**
   ```bash
   git clone https://github.com/iharshitmaurya/HeyMac.git
   cd HeyMac
   ```

2. **Build the application:**
   You can run the build script to compile the application and generate a `.dmg` file in the `dist` folder:
   ```bash
   ./scripts/build-app.sh
   ```

3. **Install:**
   Once built, go to the `dist` folder and drag **HeyMac.app** into your `/Applications` folder, or just double-click it to run it directly.

> ⚠️  **IMPORTANT:** Because you compiled it yourself, macOS might ask for permission the first time you run it. Go to **System Settings → Privacy & Security → Open Anyway** if macOS blocks it.

---

## 🔒 Private & Secure by Design

Security is not an afterthought; it is the foundation of Hey Mac. This application operates on a strict zero-trust, local-only model.

> **100% On-Device Processing:** All facial recognition is handled locally by the Apple Neural Engine via Core ML. **No data ever leaves your machine.**

*   **Zero Photo Storage:** Hey Mac does not save images of your face. It generates a mathematical, numeric embedding of your facial structure, encrypted securely within the native **macOS Keychain**.
*   **Advanced Anti-Spoofing:** Built-in liveness detection ensures a physical, three-dimensional human is present. It actively rejects photographs, screens, or printed masks.
*   **Quit Protection:** If Hey Mac is securing an app, quitting the app requires biometric authentication. A persistent background launch agent ensures the security layer cannot be bypassed by force-quitting the process.
