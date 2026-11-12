// TEMP-STUB (P1-A)
//
// Why this file exists: `Utilities/Defaults.swift` (vendored) exposes
// `recordingSaveFormat` / `recordingSavePreference`, which are typed by
// `ScreenRecordingFormat` and `RecordingSavePreference`. Both enums are declared
// at the top of `Capture/RecordingEngine.swift`, which is NOT vendored (1364
// lines: AVFoundation capture, audio devices, GIF/MP4 export, recording HUD — the
// whole screen-recording subsystem, out of scope for the capture/editor port).
//
// Behaviour: these are the pure value types copied verbatim from upstream, so
// behaviour is identical to the real thing. They are marked TEMP-STUB because the
// declarations are duplicated, and must be deleted the moment
// `Capture/RecordingEngine.swift` (or an equivalent) is added to the target —
// otherwise the two declarations collide.

import Foundation

/// TEMP-STUB (P1-A) — verbatim copy from the top of `Capture/RecordingEngine.swift`.
enum ScreenRecordingFormat: String, CaseIterable {
    case mp4
    case gif

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return L10n.recordingFormatMP4
        case .gif: return L10n.recordingFormatGIF
        }
    }
}

/// TEMP-STUB (P1-A) — verbatim copy from the top of `Capture/RecordingEngine.swift`.
enum RecordingSavePreference: String, CaseIterable {
    case manual
    case gif
    case mp4

    var displayName: String {
        switch self {
        case .manual: return L10n.recordingFormatManual
        case .gif: return L10n.recordingFormatGIF
        case .mp4: return L10n.recordingFormatMP4
        }
    }

    var format: ScreenRecordingFormat? {
        switch self {
        case .manual: return nil
        case .gif: return .gif
        case .mp4: return .mp4
        }
    }
}
