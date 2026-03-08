import Foundation

struct TextSegment: Identifiable {
    let id = UUID()
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let title: String

    func contains(_ time: TimeInterval) -> Bool {
        time >= startSeconds && time < endSeconds
    }
}
