# Android to Figma Screenshot Automation

Android app that watches for new screenshots and sends them over Wi-Fi to a Mac menu bar app, which saves them to a folder and pastes them into Figma. See PROTOCOL.md for the wire protocol.

```
Screenshot Sync — setup guide
==============================

This package contains:
  - ScreenshotSync.dmg   the Mac menu bar app
  - ScreenshotSync.apk   the Android app

1. Install the Mac app
-----------------------
Open ScreenshotSync.dmg and drag Screenshot Sync into Applications.

The app is signed with a local development identity, not a notarized Apple
Developer ID, so the first time you open it macOS Gatekeeper may warn that
it "cannot be opened" or "is damaged." If that happens: right-click (or
Control-click) the app in Applications and choose "Open," then confirm in
the dialog that appears. You only need to do this once.

On first launch, a dialog will ask for Accessibility access — this is what
lets the app paste incoming screenshots directly into Figma. Click "Open
System Settings" and enable Screenshot Sync under Privacy & Security >
Accessibility. If you skip this, screenshots will still be saved to your
"Mobile Screenshots" folder on the Desktop; they just won't auto-paste.

The app runs as a menu bar icon (small photo icon, top right of your
screen) — there's no Dock icon or main window.

2. Install the Android app
---------------------------
ScreenshotSync.apk is not on the Play Store, so you'll need to sideload it:
  - Copy the APK to your phone (email, cloud drive, USB, etc.)
  - Open it from a Files app and tap Install
  - You may need to enable "Install unknown apps" for whichever app you
    used to open the APK (Settings will prompt you if so)

On first launch, grant:
  - Camera        (for scanning the pairing QR code)
  - Notifications  (for the "watching for screenshots" status)
  - Photos and videos → choose "Allow all" specifically — "Select
    photos..." will NOT work, since the app can't predict which future
    screenshot to pre-select

3. Pair the two
----------------
  - On the Mac, click the menu bar icon, then "Pair New Device…"
  - On the phone, tap "Pair with Mac" and scan the QR code shown on the Mac
  - Both sides should confirm pairing succeeded

4. Start watching
-------------------
On the phone, tap "Start Watching." From then on, any screenshot you take
is automatically sent to the Mac — saved into ~/Desktop/Mobile Screenshots,
and pasted directly onto the canvas if Figma is the frontmost app.

Notes
-----
  - Both devices need to be on the same WiFi network.
  - Pairing only needs to happen once — after that the phone finds the Mac
    automatically via Bonjour, even if the Mac's IP address changes.
  - If you ever want to remove a paired device, use the trash icon next to
    its name in the Mac app's menu bar popover.
```
