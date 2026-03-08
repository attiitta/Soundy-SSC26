import UIKit

struct ColorSegment: Identifiable {
    let id = UUID()
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let color: UIColor

    func contains(_ time: TimeInterval) -> Bool {
        time >= startSeconds && time < endSeconds
    }
}
