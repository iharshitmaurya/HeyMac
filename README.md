<div align="center">

<img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Cstyle%3E.b%7Bstroke:%230A84FF;animation:p 1.5s infinite alternate%7D.el%7Btransform-origin:35px 42px;animation:k 4s infinite%7D.er%7Btransform-origin:65px 42px;animation:k 4s infinite%7D.s%7Banimation:s 3s ease-in-out infinite%7D@keyframes p%7B0%25%7Bopacity:.4%7D100%25%7Bopacity:1%7D%7D@keyframes k%7B0%25,92%25,98%25,100%25%7Btransform:scaleY(1)%7D95%25%7Btransform:scaleY(.1)%7D%7D@keyframes s%7B0%25,100%25%7Btransform:translateY(20px);opacity:0%7D10%25,90%25%7Bopacity:1%7D50%25%7Btransform:translateY(80px)%7D%7D%3C/style%3E%3Crect width='100' height='100' rx='22' fill='%231C1C1E'/%3E%3Cpath class='b' d='M30 20h-5c-2.8 0-5 2.2-5 5v5m50-10h5c2.8 0 5 2.2 5 5v5M20 70v5c0 2.8 2.2 5 5 5h5m50-10v5c0 2.8-2.2 5-5 5h-5' fill='none' stroke-width='6' stroke-linecap='round'/%3E%3Ccircle class='el' cx='35' cy='42' r='5' fill='%23FFF'/%3E%3Ccircle class='er' cx='65' cy='42' r='5' fill='%23FFF'/%3E%3Cpath d='M50 50v8M40 68q10 10 20 0' fill='none' stroke='%23FFF' stroke-width='5' stroke-linecap='round'/%3E%3Cline class='s' x1='20' y1='0' x2='80' y2='0' stroke='%230A84FF' stroke-width='3' stroke-linecap='round'/%3E%3C/svg%3E" width="90" alt="Animated Hey Mac Logo" style="margin-bottom: 20px; box-shadow: 0 10px 20px rgba(0,0,0,0.15); border-radius: 22px;"/>

# Hey Mac

**Your face is the password.**<br>
Unlock your Mac's lock screen and secure individual apps with a single look.

<br>

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=for-the-badge&logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Native-0071E3?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-Native-F05138?style=for-the-badge&logo=swift&logoColor=white)
![Privacy](https://img.shields.io/badge/100%25-On--Device-34C759?style=for-the-badge&logo=shield&logoColor=white)

[**Download Latest Release**](https://github.com/iharshitmaurya/HeyMac/releases/latest) &nbsp;&nbsp;•&nbsp;&nbsp; [Build Instructions](#-build-from-source) &nbsp;&nbsp;•&nbsp;&nbsp; [Architecture](#-how-it-works)

</div>

<br>

---

## ✨ Features

Hey Mac bridges the gap between iOS-level convenience and macOS security, bringing native-feeling facial recognition to your desktop.

*   🔓 **Zero-Touch Unlock:** Wake your Mac, look at the screen, and you're immediately logged in. No keyboard required.
*   🛡️ **Application-Level Shielding:** Protect sensitive apps (Messages, Notes, Mail). Unauthorized viewers see a blurred interface until your identity is verified via Face, Touch ID, or password.
*   🌫️ **Adaptive Privacy Blurs:** Choose your obfuscation level. Blur the entire display for maximum privacy, or strictly blur the locked application window to maintain workflow context.
*   ⏱️ **Intelligent Relock Policies:** Granular control per application. Require authentication immediately upon launch, after a set duration (5-15 mins), or gracefully lock after you switch focus away from the app.
*   🏝️ **Dynamic Notch Island:** A fluid, native-feeling UI drops down from the macOS notch, providing instant visual feedback during biometric scans.
*   🧑‍🚀 **Frictionless Onboarding:** A polished 6-step setup wizard guides you through camera permissions, facial enrollment, testing, and security preferences.

---

## 🔒 Private & Secure by Design

Security is not an afterthought; it is the foundation of Hey Mac. This application operates on a strict zero-trust, local-only model.

> **100% On-Device Processing:** All facial recognition is handled locally by the Apple Neural Engine via Core ML. **No data ever leaves your machine.**

*   **Zero Photo Storage:** Hey Mac does not save images of your face. It generates a mathematical, numeric embedding of your facial structure, encrypted securely within the native **macOS Keychain**.
*   **Advanced Anti-Spoofing:** Built-in liveness detection ensures a physical, three-dimensional human is present. It actively rejects photographs, screens, or printed masks.
*   **Daemon Protection:** If Hey Mac is securing an app, quitting the daemon requires biometric authentication. A persistent background launch agent ensures the security layer cannot be bypassed by force-quitting the process.

---

## 🧠 How it Works

The facial recognition pipeline utilizes state-of-the-art ArcFace embeddings paired with custom liveness detection models, optimized for Apple Silicon.

```mermaid
graph LR
    A[Camera Frame] -->|Capture| B(Face Detection & Alignment)
    B --> C{Liveness Check}
    C -- Failed --> X[Reject: Stay Locked]
    C -- Passed --> D(Generate ArcFace Embedding)
    D --> E{Compare against<br/>Keychain Profile}
    E -- Match --> F((Unlock / Reveal App))
    E -- Mismatch --> G[Fallback to Touch ID / Password]

    classDef default fill:#1E1E1E,stroke:#333,stroke-width:1px,color:#fff;
    classDef success fill:#103619,stroke:#34C759,stroke-width:1px,color:#fff;
    classDef fail fill:#3B1214,stroke:#FF3B30,stroke-width:1px,color:#fff;
    class F success;
    class X fail;