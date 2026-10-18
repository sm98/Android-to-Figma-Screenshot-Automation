import AppKit
import ApplicationServices

/// Shows a clear, explicit dialog the first time the app launches without Accessibility access,
/// rather than relying only on macOS's system prompt (which can be easy to miss or, for
/// unsigned/locally-signed apps, doesn't always surface reliably).
enum AccessibilityOnboarding {
    private static let hasShownKey = "hasShownAccessibilityOnboarding"

    static func promptIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        guard !UserDefaults.standard.bool(forKey: hasShownKey) else { return }
        UserDefaults.standard.set(true, forKey: hasShownKey)

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Needed"
            alert.informativeText = """
            Screenshot Sync uses Accessibility access to paste incoming screenshots directly into Figma.

            Without it, screenshots will still be saved to your Mobile Screenshots folder — they just won't auto-paste.

            Click "Open System Settings" below, then enable Screenshot Sync in the Accessibility list.
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")
            alert.alertStyle = .informational

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            }
        }
    }
}
