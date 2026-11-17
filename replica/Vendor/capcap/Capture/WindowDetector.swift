import AppKit
import CoreGraphics

struct DetectedWindow: Sendable {
    private static let selectableLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.normalWindow)),
        Int(CGWindowLevelForKey(.floatingWindow)),
        Int(CGWindowLevelForKey(.modalPanelWindow)),
        Int(CGWindowLevelForKey(.utilityWindow)),
        Int(CGWindowLevelForKey(.popUpMenuWindow))
    ]

    let name: String
    let windowID: CGWindowID
    let layer: Int
    let frame: CGRect   // CG coordinates (global, top-left origin)
    let ownerPID: pid_t
    /// Floating-or-above window that belongs to this product: either this
    /// process's own HUD (magnifier lens / drag hint) or a twin instance of the
    /// same bundle. Those surfaces follow the pointer and must never become the
    /// snap-guide target, or the guide would outline its own cursor chip.
    let isProductChrome: Bool

    var usesCompositedScreenBackdrop: Bool {
        layer >= 20
    }

    var isSelectableCaptureTarget: Bool {
        // Keep real AppKit content windows and popup menus selectable while
        // excluding menu-bar chrome, insertion points, cursors, and other
        // transient WindowServer surfaces that would steal hover selection.
        Self.selectableLayers.contains(layer)
    }
}

enum WindowDetectionError: LocalizedError, Sendable {
    case invalidPrimaryScreenArea(CGFloat)
    case windowListUnavailable
    case invalidWindowListPayload

    var errorDescription: String? {
        switch self {
        case .invalidPrimaryScreenArea(let area):
            return "Invalid primary screen area for window detection: \(area)"
        case .windowListUnavailable:
            return "Core Graphics did not return a window list"
        case .invalidWindowListPayload:
            return "Core Graphics returned an unexpected window list payload"
        }
    }
}

class WindowDetector {
    private var windows: [DetectedWindow] = []

    /// The app that owns keyboard focus when a capture starts.
    struct FocusOwner: Equatable {
        let pid: pid_t
        let isRegularApp: Bool
    }

    private static let popUpMenuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
    private static let normalLayer = Int(CGWindowLevelForKey(.normalWindow))
    private static let panelLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.floatingWindow)),
        Int(CGWindowLevelForKey(.modalPanelWindow)),
        Int(CGWindowLevelForKey(.utilityWindow))
    ]

    /// Check before claiming keyboard focus or activating capcap: open menus
    /// and launcher-style panels (Raycast, Spotlight, menu bar popovers) hide
    /// as soon as their app loses focus, before ScreenCaptureKit can freeze
    /// their pixels.
    static func displaysWithFocusSensitiveWindows(in targets: [ScreenSnapshotTarget]) -> Set<CGDirectDisplayID> {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let focusOwner = NSWorkspace.shared.frontmostApplication.flatMap { app -> FocusOwner? in
            guard app.processIdentifier != ownPID else { return nil }
            return FocusOwner(
                pid: app.processIdentifier,
                isRegularApp: app.activationPolicy == .regular
            )
        }
        let sensitiveRects: [CGRect] = windows.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 1, rect.height > 1,
                  isFocusSensitive(layer: layer, ownerPID: ownerPID, focusOwner: focusOwner)
            else { return nil }
            return rect
        }
        return Set(targets.filter { target in
            sensitiveRects.contains { $0.intersects(target.bounds) }
        }.map(\.displayID))
    }

    /// Whether a visible window is likely to disappear once capcap takes focus.
    /// Popup menus close for any owner. The focused app's floating, modal and
    /// utility panels usually hide on deactivation, and every content window
    /// of a focused accessory app (no Dock icon) is treated as transient.
    static func isFocusSensitive(
        layer: Int,
        ownerPID: pid_t,
        focusOwner: FocusOwner?
    ) -> Bool {
        if layer == popUpMenuLayer { return true }
        guard let focusOwner, ownerPID == focusOwner.pid else { return false }
        if panelLayers.contains(layer) { return true }
        return layer == normalLayer && !focusOwner.isRegularApp
    }

    /// Build an immutable window snapshot without touching AppKit screen state
    /// or this detector's mutable state. Safe to call from a background queue.
    static func snapshot(
        primaryScreenArea: CGFloat
    ) -> Result<[DetectedWindow], WindowDetectionError> {
        guard primaryScreenArea.isFinite, primaryScreenArea > 0 else {
            return .failure(.invalidPrimaryScreenArea(primaryScreenArea))
        }

        guard let rawInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) else {
            return .failure(.windowListUnavailable)
        }
        guard let infoList = rawInfoList as? [[String: Any]] else {
            return .failure(.invalidWindowListPayload)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier

        let detectedWindows: [DetectedWindow] = infoList.compactMap { info -> DetectedWindow? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsNS = info[kCGWindowBounds as String] as? NSDictionary,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 0
            else { return nil }

            // Keep this app's own menus/popups detectable so capcap can capture
            // its visible transient UI. Only screen-saver-level chrome (toasts,
            // tooltips, countdown and progress panels) is excluded.
            // The capture overlay itself is created after refresh(), so it is
            // never in this snapshot.
            if pid == ownPID && layer >= Int(CGWindowLevelForKey(.screenSaverWindow)) {
                return nil
            }

            // Skip fully transparent windows (invisible system overlays)
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                return nil
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsNS as CFDictionary, &rect) else { return nil }
            guard rect.width > 1, rect.height > 1 else { return nil }

            // For windows above normal app levels (dock, menu bar, popups, etc.),
            // skip near-full-screen ones — these are typically invisible system
            // overlays (e.g. input method backgrounds) that block real windows.
            if layer >= 20 {
                if rect.width * rect.height > primaryScreenArea * 0.8 {
                    return nil
                }
            }

            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            // Only floating-or-above windows can be product chrome, and only a
            // *twin* process needs a bundle lookup. Normal windows (the vast
            // majority of an enumeration) therefore cost no launchd round-trip.
            let chrome: Bool
            if pid == ownPID {
                chrome = layer >= Int(CGWindowLevelForKey(.screenSaverWindow))
            } else if layer >= Int(NSWindow.Level.floating.rawValue) {
                let owner = ownerBundleID(for: pid, ownerName: name)
                chrome = owner != nil && owner == ownBundleID
            } else {
                chrome = false
            }
            let detected = DetectedWindow(
                name: name,
                windowID: windowID,
                layer: layer,
                frame: rect,
                ownerPID: pid,
                isProductChrome: chrome
            )

            guard detected.isSelectableCaptureTarget else { return nil }
            return detected
        }

        return .success(detectedWindows)
    }

    /// Commit a previously-created value snapshot to this detector.
    func apply(_ detectedWindows: [DetectedWindow]) {
        windows = detectedWindows
    }

    /// The cached window list, front to back.
    ///
    /// Read-only: the drag snap scans this 8Hz cache for the nearest window
    /// edge, exactly like the hover path uses `windowAt(cgPoint:)`. Nothing
    /// here enumerates the WindowServer.
    var cachedWindows: [DetectedWindow] { windows }

    /// High-layer system surfaces (menu bar, Dock, popups) are often only a
    /// translucent foreground when captured as independent windows. Capture
    /// their already-composited screen pixels instead.
    func usesCompositedScreenBackdrop(forWindowID windowID: CGWindowID) -> Bool {
        windows.first { $0.windowID == windowID }?.usesCompositedScreenBackdrop ?? false
    }

    /// Bundle identifiers for the few (floating-or-above) windows that can be
    /// twin chrome. `NSRunningApplication` is a launchd round-trip and the list
    /// is refreshed at 8Hz, so a hit is cached. The cache is validated against
    /// the window's owner name, so a reused PID from another app cannot inherit
    /// the previous owner's bundle and be misclassified.
    private struct OwnerIdentity {
        let name: String
        let bundleID: String?
    }

    private static let ownerIdentityLock = NSLock()
    private static var ownerIdentityCache: [pid_t: OwnerIdentity] = [:]

    private static func ownerBundleID(for pid: pid_t, ownerName: String) -> String? {
        ownerIdentityLock.lock()
        defer { ownerIdentityLock.unlock() }
        if let cached = ownerIdentityCache[pid], cached.name == ownerName {
            return cached.bundleID
        }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        ownerIdentityCache[pid] = OwnerIdentity(name: ownerName, bundleID: bundleID)
        return bundleID
    }

    /// Product chrome must never be a hover target: it follows the pointer and
    /// the guide would outline its own cursor chip.
    ///
    /// - This process: only screen-saver-level surfaces (the overlay panels and
    ///   the lens/chip HUD, both `.screenSaver` and above). Own popup menus sit
    ///   lower and stay capturable, as before. The controller additionally
    ///   filters its *own* window numbers, which covers a pooled overlay panel
    ///   that is still at its default level while being prepared.
    /// - A twin instance of this product (same bundle identifier): any
    ///   floating-or-above window is its HUD.
    static func isProductChrome(
        layer: Int,
        ownerPID: pid_t,
        ownPID: pid_t,
        ownerBundleID: String?,
        ownBundleID: String?
    ) -> Bool {
        if ownerPID == ownPID {
            return layer >= Int(CGWindowLevelForKey(.screenSaverWindow))
        }
        guard layer >= Int(NSWindow.Level.floating.rawValue) else { return false }
        guard let ownBundleID, let ownerBundleID else { return false }
        return ownerBundleID == ownBundleID
    }

    /// Return the topmost window whose frame contains `cgPoint`
    /// (CG coordinates: origin at top-left of primary display, y increases downward).
    func windowAt(cgPoint: CGPoint) -> DetectedWindow? {
        // CGWindowListCopyWindowInfo returns windows in front-to-back z-order,
        // so the first hit is the topmost window. Own/twin product chrome is
        // already classified and skipped here.
        return windows.first {
            $0.isSelectableCaptureTarget && !$0.isProductChrome && $0.frame.contains(cgPoint)
        }
    }
}
