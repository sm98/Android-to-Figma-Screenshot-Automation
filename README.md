# Android to Figma Screenshot Automation

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: Android 8+](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)
![Platform: macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Kotlin](https://img.shields.io/badge/Kotlin-Jetpack%20Compose-7F52FF?logo=kotlin&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)

Take a screenshot on your Android phone and have it appear in Figma on your Mac, with no cable, AirDrop or manual copy-paste.

An Android app watches for new screenshots and sends each one over your local Wi-Fi to a small macOS menu bar app. The Mac app saves every screenshot to a folder and, if Figma is the frontmost app, pastes it straight onto the canvas.

```
┌─────────────────────┐   Wi-Fi (TLS, cert-pinned)   ┌──────────────────────────┐
│  Android app        │ ───────────────────────────▶ │  Mac menu bar app        │
│  watches MediaStore │   POST /upload  (raw image)  │  saves to ~/Desktop/     │
│  for new screenshots│                              │    Mobile Screenshots    │
└─────────────────────┘                              │  pastes into Figma (⌘V)  │
        ▲  finds the Mac via Bonjour (mDNS)          └──────────────────────────┘
        └── one-time QR pairing
```

## Contents

- [Quick start](#quick-start)
- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Install and use](#install-and-use)
- [Build from source](#build-from-source)
- [Troubleshooting](#troubleshooting)
- [Privacy and security](#privacy-and-security)
- [Project layout](#project-layout)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Quick start

1. Build and open the Mac app, then grant Accessibility access when asked.
2. Install the Android app and grant Camera, Notifications and **Photos → Allow all**.
3. Mac menu bar icon → **Pair New Device…**, then on the phone **Pair with Mac** and scan the QR.
4. Tap **Start Watching** on the phone and take a screenshot. With Figma frontmost, it lands on the canvas.

Both devices must be on the same Wi-Fi network. Details are in [Install and use](#install-and-use).

## Features

- **Background detection**: a foreground service watches `MediaStore` for new screenshots. A short debounce plus an `IS_PENDING` check avoids uploading half-written files.
- **One-time QR pairing**: the Mac shows a QR code, the phone scans it once, and from then on the two find each other automatically.
- **Secure by default**: TLS with certificate pinning (no CA, no plain HTTP), a single-use pairing token, and a long-lived bearer token per paired phone.
- **Survives IP changes**: the Mac advertises itself with Bonjour (`_screenshotsync._tcp`), so the phone re-discovers it even after a router reboot or Wi-Fi change.
- **Reliable delivery**: failed uploads go into a local Room queue and retry with backoff (5s, 15s, 1m, 5m, then every 15m, up to 24h). The Mac dedupes by SHA-256, so retries never produce duplicates.
- **Figma auto-paste**: when Figma is frontmost, the image is resized to **360px wide** (aspect ratio kept), put on the clipboard, pasted with a synthetic ⌘V, then deselected with Escape so the next paste adds a new image instead of replacing the previous one.
- **Always saved**: the original full-resolution screenshot goes to `~/Desktop/Mobile Screenshots`, whether or not Figma is open.

## How it works

| Piece | Tech |
|---|---|
| Android app | Kotlin, Jetpack Compose, foreground service + `ContentObserver`, CameraX + ML Kit (QR scan), OkHttp with a custom pinned `TrustManager`, `NsdManager` (mDNS), Room (retry queue), EncryptedSharedPreferences |
| Mac app | Swift / SwiftUI `MenuBarExtra`, hand-rolled HTTP/1.1 server on `Network.framework` (`NWListener` with TLS), Bonjour advertisement, Keychain (TLS identity and paired devices), `CGEvent` for the Figma paste |
| Protocol | See [PROTOCOL.md](PROTOCOL.md): pairing handshake, `/upload` format, retry and security rules |

**Pairing flow:** the Mac generates a self-signed TLS certificate once. Its QR code contains the Mac's address, certificate fingerprint and a 3-minute single-use token. The phone connects trusting only that fingerprint, exchanges the token for a bearer token, and stores it encrypted. Every later upload re-finds the Mac through Bonjour and authenticates with that bearer token.

**Upload flow:**

1. The phone sees a new screenshot, waits for it to finish writing, and reads the bytes.
2. It looks up the Mac via Bonjour and sends `POST /upload` with the bearer token and a SHA-256 checksum.
3. The Mac checks the token and checksum, ignores duplicates seen in the last 5 minutes, and saves the file.
4. If Figma is frontmost, the Mac pastes a 360px-wide copy.
5. On any failure the phone keeps the item in its queue and retries later.

**Why the Figma paste is clipboard + keystrokes:** Figma's APIs can't insert an image into an open desktop file from outside. Simulating ⌘V is the only external route, which is why it needs macOS Accessibility permission and only fires when Figma is the frontmost app. A proper Figma plugin would allow precise sizing and placement and is a possible future improvement.

## Requirements

- Mac: macOS 13 or later
- Android: 8.0 or later (API 26+), on the same Wi-Fi network as the Mac
- Figma desktop app (`com.figma.Desktop`) for the auto-paste

## Install and use

### 1. Mac app

Build it (see [Build from source](#build-from-source)) or open `ScreenshotSync.dmg` and drag **Screenshot Sync** into Applications.

The app is not notarized. On first open, macOS may say it can't be opened: right-click the app, choose **Open**, then confirm. You only need to do this once.

On first launch it asks for **Accessibility** access. Click *Open System Settings* and enable Screenshot Sync under Privacy & Security → Accessibility. Without it, screenshots are still saved but won't auto-paste. macOS may also ask to allow **local network** access: allow it, since this is how the phone reaches the Mac. The app lives in the menu bar (small photo icon) with no Dock icon.

### 2. Android app

Sideload the APK (copy it to the phone, open it, allow "Install unknown apps" if prompted). On first launch grant:

- **Camera**: to scan the pairing QR
- **Notifications**: for the "watching for screenshots" status
- **Photos and videos → Allow all**: "Select photos" will not work, because the app can't know in advance which future screenshots to allow

### 3. Pair

1. On the Mac: menu bar icon → **Pair New Device…** (a QR code appears)
2. On the phone: **Pair with Mac** → scan the QR
3. Both sides confirm. Pairing is one-time, and each QR code can only be used once.

### 4. Use

On the phone tap **Start Watching**. Take screenshots as usual. They land in `~/Desktop/Mobile Screenshots` and, if Figma is frontmost, on the canvas. To unpair a phone, use the trash icon next to its name in the Mac popover.

## Build from source

### Mac app

Needs Xcode (Swift 5.9+) on macOS 13+.

```bash
cd mac-app
./build_app.sh        # debug build → ScreenshotSync.app
./build_release.sh    # release build → ScreenshotSync.app + ScreenshotSync.dmg
```

The scripts sign with a local identity named **"ScreenshotSync Local Dev"**. Use a *stable* identity: with ad-hoc signing (`-`), macOS forgets Keychain and Accessibility grants on every rebuild. Create one once with a self-signed code-signing certificate (Keychain Access → Certificate Assistant → Create a Certificate → Code Signing), or edit the `codesign` line in the scripts to use your own identity.

### Android app

Needs JDK 17 and the Android SDK (platform 34).

```bash
cd android-app
echo "sdk.dir=/path/to/your/android/sdk" > local.properties
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Troubleshooting

**Screenshots arrive but nothing pastes into Figma**
Figma must be the frontmost app when the screenshot arrives, and Screenshot Sync must be enabled under Privacy & Security → Accessibility. The popover shows "Figma auto-paste ready" when it is. If you rebuilt the app with a different signing identity, remove the old entry in the Accessibility list and add the new app again.

**Each paste replaces the previous image in Figma**
The app presses Escape after pasting to deselect. If you click an image in Figma between screenshots, that image is selected and the next paste replaces its fill. Click empty canvas first.

**The phone says it can't find the Mac**
Check both are on the same Wi-Fi network and that the Mac app is running (menu bar icon). Some routers block devices from talking to each other ("client isolation" or "AP isolation"), and guest networks often do. Also check that macOS local network access is allowed for Screenshot Sync.

**Pairing fails with "invalid or expired pairing token"**
Each QR code works once and expires after 3 minutes. Close the pairing sheet and open **Pair New Device…** again for a fresh one.

**New screenshots are never detected**
Open the phone's app permissions and make sure Photos and videos is set to **Allow all**, not "Select photos". Also check that Start Watching is on and that the "watching for screenshots" notification is showing.

**The Mac app seems stuck on first launch**
macOS can show Keychain or local network permission prompts at startup, and the app waits on them. Look for a dialog on screen and approve it.

**macOS says the app can't be opened**
It isn't notarized. Right-click the app and choose **Open**.

**Android shows a "16 KB compatibility" warning**
This appears on debug builds on Android 15 and later, because some bundled native libraries aren't 16 KB-aligned yet. It doesn't affect how the app runs.

## Privacy and security

- Everything stays on your local network. Nothing is sent to the internet and there are no accounts or analytics.
- Traffic uses TLS, and the phone trusts only the Mac's pinned certificate fingerprint from the pairing QR, not any certificate authority.
- A pairing QR is single-use and valid for 3 minutes. Each phone then gets its own bearer token, stored in Android's encrypted storage and in the Mac's Keychain.
- Remove a paired phone with the trash icon in the Mac popover, and its token stops working immediately.
- Only screenshots are uploaded. The app checks each new image's name and folder to decide if it's a screenshot, and never sends other photos.

## Project layout

```
PROTOCOL.md     wire protocol (pairing, upload, retries, security)
mac-app/        Swift package: menu bar app, TLS server, Bonjour, Figma paste
android-app/    Kotlin / Compose app: watcher service, QR pairing, upload client
```

## Known limitations

- The Mac app is signed with a local identity, not notarized, so expect the Gatekeeper prompt above. The APK is debug-signed.
- Figma paste goes through the clipboard and works only while Figma is frontmost. Images are always pasted at 360px wide at the viewport centre, and there is no automatic layout or spacing.
- Android-only: iOS is not supported.
- Keep the project outside iCloud-synced folders (for example `~/Desktop` or `~/Documents`): iCloud renames build files mid-write and breaks Gradle builds.

## Contributing

Issues and pull requests are welcome. For protocol changes, update [PROTOCOL.md](PROTOCOL.md) alongside the code so both apps stay in sync. Ideas that would help most: a Figma plugin for exact sizing and placement, release builds on the Releases page, and notarizing the Mac app.

## License

[MIT](LICENSE) © 2026 Sanoop Menon
