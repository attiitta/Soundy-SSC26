import SwiftUI

/// Instrument type
enum Instrument: String, CaseIterable, Identifiable {
    case triangle = "triangle"
    case treeChime = "treeChime"
    case cowbell = "cowbell"

    var id: String { rawValue }

    /// Vertical offset of flowing circle (0 = center, negative = top, positive = bottom)
    var laneOffsetY: CGFloat {
        switch self {
        case .triangle: return 0
        case .treeChime: return -80
        case .cowbell: return 80
        }
    }

    /// Particle color per lane
    var particleColor: Color {
        switch self {
        case .treeChime: return Color(red: 0.2, green: 0.5, blue: 0.95)
        case .triangle:  return Color(red: 1, green: 0.55, blue: 0.2)
        case .cowbell:   return Color(red: 0.2, green: 0.75, blue: 0.4)
        }
    }

    /// Base haptic intensity (0…1): top=strong, center=medium, bottom=light
    var hapticIntensityBase: CGFloat {
        switch self {
        case .treeChime: return 1.0
        case .triangle:  return 0.65
        case .cowbell:   return 0.35
        }
    }

    /// Accessibility / VoiceOver display name
    var accessibleName: String {
        switch self {
        case .triangle: return "Triangle"
        case .treeChime: return "Tree chime"
        case .cowbell: return "Cowbell"
        }
    }
}

/// One note: when to hit and which instrument
struct InstrumentHitSegment: Identifiable {
    let id = UUID()
    /// Time (seconds) when the note reaches the tap zone
    let hitAtSeconds: TimeInterval
    let instrument: Instrument
    /// If true, hit does not add to score (e.g. trial note)
    let excludeFromScore: Bool

    init(hitAtSeconds: TimeInterval, instrument: Instrument, excludeFromScore: Bool = false) {
        self.hitAtSeconds = hitAtSeconds
        self.instrument = instrument
        self.excludeFromScore = excludeFromScore
    }

    /// Seconds before hit time when the note appears
    static let leadSeconds: TimeInterval = 4.0
    /// Offset (pt) from tap zone when note appears (kept on-screen for typical widths)
    static let startOffsetPt: CGFloat = 380
    /// Movement speed (pt/sec)
    static let speedPtPerSec: CGFloat = 95

    /// Seconds after passing zone before note disappears
    static let exitDuration: TimeInterval = 100.0 / 95.0

    /// Time range when this note is visible
    var visibleStartSeconds: TimeInterval { hitAtSeconds - Self.leadSeconds }
    var visibleEndSeconds: TimeInterval { hitAtSeconds + Self.exitDuration }

    /// Whether the note is visible at the given time
    func isVisible(at time: TimeInterval) -> Bool {
        time >= visibleStartSeconds && time < visibleEndSeconds
    }

    /// Button X position at given time (0 = tap zone left edge; negative = left of zone)
    func buttonX(at time: TimeInterval) -> CGFloat {
        guard isVisible(at: time) else { return -Self.startOffsetPt - 100 }
        if time < hitAtSeconds {
            let elapsed = time - visibleStartSeconds
            return -Self.startOffsetPt + CGFloat(elapsed) * Self.speedPtPerSec
        } else {
            let elapsed = time - hitAtSeconds
            return CGFloat(elapsed) * Self.speedPtPerSec
        }
    }

    /// Hit timing tolerance (seconds)
    static let hitWindowSeconds: TimeInterval = 0.2
}
