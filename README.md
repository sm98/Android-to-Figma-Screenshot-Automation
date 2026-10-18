# Android to Figma Screenshot Automation

Take a screenshot on your Android phone and have it show up in Figma on your Mac, with no cable, AirDrop or manual copy-paste.

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

## Features

- **Background detection**: a foreground service watches `MediaStore` for new screenshots. A short debounce plus an `IS_PENDING` check avoids uploading half-written files.
- **One-time QR pairing**: the Mac shows a QR code, the phone scans it once, and from then on the two find each other automatically.
- **Secure by default**: TLS with certificate pinning (no CA, no plain HTTP), a single-use pairing token, and a long-lived bearer token per paired phone.
- **Survives IP changes**: the Mac advertises itself with Bonjour (`_screenshotsync._tcp`), so the phone re-discovers it even after a router reboot or Wi-Fi change.
- **Reliable delivery**: failed uploads go into a local Room queue and retry with backoff (5s, 15s, 1m, 5m, then every 15m, up to 24h). The Mac dedupes by SHA-256, so retries never produce duplicates.
- **Figma auto-paste**: when Figma is frontmost, the image is resized to **360px wide** (aspect ratio kept), put on the clipboard, pasted with a synthetic ⌘V, then deselected with Escape so the next paste adds a new image instead of replacing the previous one.
- The original full-resolution screenshot is always saved to `~/Desktop/Mobile Screenshots`, whether or not Figma is open.

## How it works

| Piece | Tech |
|---|---|
| Android app | Kotlin, Jetpack Compose, foreground service + `ContentObserver`, CameraX + ML Kit (QR scan), OkHttp with a custom pinned `TrustManager`, `NsdManager` (mDNS), Room (retry queue), EncryptedSharedPreferences |
| Mac app | Swift / SwiftUI `MenuBarExtra`, hand-rolled HTTP/1.1 server on `Network.framework` (`NWListener` with TLS), Bonjour advertisement, Keychain (TLS identity and paired devices), `CGEvent` for the Figma paste |
| Protocol | See [PROTOCOL.md](PROTOCOL.md): pairing handshake, `/upload` format, retry and security rules |

**Pairing flow:** the Mac generates a self-signed TLS certificate once. Its QR code contains the Mac's address, certificate fingerprint and a 3-minute single-use token. The phone connects trusting only that fingerprint, exchanges the token for a bearer token, and stores it encrypted. Every later upload re-finds the Mac through Bonjour and authenticates with that bearer token.

**Why the Figma paste is clipboard + keystrokes:** Figma's APIs can't insert an image into an open desktop file from outside. Simulating ⌘V is the only external route, which is why it needs macOS Accessibility permission and only fires when Figma is the frontmost app. A proper Figma plugin would allow precise sizing and placement and is a possible future improvement.

## Requirements

- Mac: macOS 13+
- Android: 8.0+ (API 26+), on the same Wi-Fi network as the Mac
- Figma desktop app (`com.figma.Desktop`) for the auto-paste

## Install and use

### 1. Mac app

Build it (see below) or open `ScreenshotSync.dmg` and drag **Screenshot Sync** into Applications.

The app is not notarized. On first open, macOS may say it can't be opened: right-click the app, choose **Open**, then confirm. You only need to do this once.

On first launch it asks for **Accessibility** access. Click *Open System Settings* and enable Screenshot Sync under Privacy & Security → Accessibility. Without it, screenshots are still saved but won't auto-paste. The app lives in the menu bar (small photo icon) with no Dock icon.

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
- Keep the project outside iCloud-synced folders (e.g. `~/Desktop`, `~/Documents`): iCloud renames build files mid-write and breaks Gradle builds.
