import AppKit
import ApplicationServices

enum FigmaPasteController {
    static let figmaBundleId = "com.figma.Desktop"

    /// All pasted images are resized to this exact pixel width before hitting the pasteboard —
    /// Figma pastes raster images at their native pixel size, so this is the only reliable way
    /// to get consistent widths without a real Figma-side integration.
    private static let targetWidthPixels: CGFloat = 360

    static func isFigmaFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == figmaBundleId
    }

    /// Puts the image on the general pasteboard and synthesizes ⌘V so it lands on whatever
    /// Figma page/canvas currently has focus. Requires Accessibility permission to post
    /// synthetic key events; returns false (without touching the pasteboard) if not granted.
    @discardableResult
    static func pasteImage(_ data: Data) -> Bool {
        guard AXIsProcessTrusted() else {
            print("[ScreenshotSync] Accessibility permission not granted; cannot synthesize paste")
            return false
        }

        let pasteData = ImageResizer.resizedToWidth(data, targetWidth: targetWidthPixels) ?? data

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pasteData, forType: .png)

        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let virtualKeyV: CGKeyCode = 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Figma auto-selects the freshly-pasted image, and pasting again while something is
        // selected replaces its fill instead of adding a new image. Deselect immediately after
        // so the next incoming screenshot lands as its own new image, not a replacement.
        usleep(200_000)
        let virtualKeyEscape: CGKeyCode = 0x35
        let escapeDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyEscape, keyDown: true)
        let escapeUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyEscape, keyDown: false)
        escapeDown?.flags = [] // must explicitly clear — otherwise it can inherit the ⌘ from the paste above
        escapeUp?.flags = []
        escapeDown?.post(tap: .cghidEventTap)
        escapeUp?.post(tap: .cghidEventTap)

        return true
    }
}
