import SwiftUI
import AVFoundation
import UIKit
import AudioToolbox

struct ContentView: View {
    @State private var audioPlayer: AVAudioPlayer?
    /// Short hit sound per instrument (played if available)
    @State private var hitSoundTriangle: AVAudioPlayer?
    @State private var hitSoundTreeChime: AVAudioPlayer?
    @State private var hitSoundCowbell: AVAudioPlayer?
    /// Note IDs already judged (hit / miss / vanished)
    @State private var judgedSegmentIDs: Set<UUID> = []
    /// Flowing particles (generated once on appear, random timing per window)
    @State private var instrumentSegments: [InstrumentHitSegment] = []
    /// Incremented only on hit; drives visual / haptic / audio music-box feel
    @State private var hitNumber: Int = 0
    /// Fireworks that burst on hit
    @State private var fireworks: [HitFirework] = []
    /// Show end subtitle after a short delay
    @State private var endSubtitleVisible = false
    @State private var endSubtitleScheduled = false
    /// Whether the lid has opened (false = closed, true = open animation)
    @State private var lidOpen = false
    /// Needle that “presses down” on hit (per lane); nil when idle
    @State private var pressingNeedle: Instrument? = nil
    /// Brief “Hit!” visual feedback (for deaf/hard of hearing)
    @State private var showHitFeedback = false
    /// Time ranges and colors; earlier segment wins when overlapping
   // private static let colorSegments: [ColorSegment] = [
    //    ColorSegment(startSeconds: 0.00, endSeconds: 7.11, color: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)),
     //   ColorSegment(startSeconds: 7.11, endSeconds: 15.03, color: #colorLiteral(red: 0.9764705896, green: 0.850980401, blue: 0.5490196347, alpha: 1)),
      //  ColorSegment(startSeconds: 15.03, endSeconds: 22.21, color: #colorLiteral(red: 1, green: 0.5763723254, blue: 0, alpha: 1)),
     //   ColorSegment(startSeconds: 22.21, endSeconds: 32.00, color: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)),
      //  ColorSegment(startSeconds: 32.00, endSeconds: 38.03, color: #colorLiteral(red: 1, green: 0.1491314173, blue: 0, alpha: 1)),
      //  ColorSegment(startSeconds: 38.03, endSeconds: 44.29, color: #colorLiteral(red: 0.9994240403, green: 0.9855536819, blue: 0, alpha: 1)),
      //  ColorSegment(startSeconds: 44.29, endSeconds: 64.19, color: #colorLiteral(red: 0.5791940689, green: 0.1280144453, blue: 0.5726861358, alpha: 1)),
       // ColorSegment(startSeconds: 64.19, endSeconds: 76.04, color: #colorLiteral(red: 1, green: 0.1491314173, blue: 0, alpha: 1)),
       //ColorSegment(startSeconds: 76.04, endSeconds: 88.02, color: #colorLiteral(red: 0, green: 0.9768045545, blue: 0, alpha: 1)),
       // ColorSegment(startSeconds: 88.02, endSeconds: 95.11, color: #colorLiteral(red: 1, green: 0.1491314173, blue: 0, alpha: 1)),
       // ColorSegment(startSeconds: 95.11, endSeconds: 99.02, color: #colorLiteral(red: 0.9999960065, green: 1, blue: 1, alpha: 1)),
    //]
    private static let colorSegments: [ColorSegment] = [
        ColorSegment(startSeconds: 0.00, endSeconds: 99.02, color: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)),
       ]


    /// Onboarding messages (spaced for readability)
    private static let textSegments: [TextSegment] = [
        TextSegment(startSeconds: 0.00, endSeconds: 5.00, title: "Welcome to the\nworld of the music box."),
        TextSegment(startSeconds: 6.50, endSeconds: 12.00, title: "Whether you can hear or not,\neveryone can enjoy music here."),
        TextSegment(startSeconds: 13.50, endSeconds: 19.00, title: "Tap the moving circle\nbetween the lines."),
        TextSegment(startSeconds: 21.00, endSeconds: 27.00, title: "Keep it up and complete\nyour own music box with Vivaldi’s Spring."),
        TextSegment(startSeconds: 29.00, endSeconds: 34.00, title: "Let’s go."),
    ]

    /// Track length (seconds)
    private static let trackDuration: TimeInterval = 99
    /// Particles per 20s window (default)
    private static let particlesPerTwentySeconds = 20
    /// Second window has 10; others 20 each → 10+20+20+20 = 70
    private static var totalSegmentCount: Int { 10 + 20 + 20 + 20 }
    
    /// Hit progress 0...1 (1 = all notes hit)
    private func hitProgress() -> Double {
        min(1, Double(hitNumber) / Double(Self.totalSegmentCount))
    }

    /// Track volume by hit count (0.5 → ~1.15)
    private static func volumeGain(forHitNumber n: Int) -> Float {
        let p = min(1, Double(n) / Double(totalSegmentCount))
        return Float(0.5 + p * 0.65)
    }

    /// Start time of “tap between the lines” message; no particles before this.
    private static var tapInstructionStartSeconds: TimeInterval {
        Self.textSegments.first { $0.title.contains("between the lines") }?.startSeconds ?? 13.5
    }
    /// Generate particles: none until 13.5s; one trial in 13.5–20s (excluded from score); then 10/20/20/20 per window.
    private static func makeInstrumentSegments() -> [InstrumentHitSegment] {
        let flowStart = Self.tapInstructionStartSeconds
        var segments: [InstrumentHitSegment] = []
        let lead = InstrumentHitSegment.leadSeconds
        let firstWindowEnd: TimeInterval = 20
        let trialHitMin = flowStart + lead
        let trialHitMax = firstWindowEnd - 2
        if trialHitMax > trialHitMin {
            let hitAt = TimeInterval.random(in: trialHitMin ..< trialHitMax)
            let instrument = Instrument.allCases.randomElement()!
            segments.append(InstrumentHitSegment(hitAtSeconds: hitAt, instrument: instrument, excludeFromScore: true))
        }
        var windowStart: TimeInterval = 20
        while windowStart < trackDuration {
            let windowEnd = min(windowStart + 20, trackDuration)
            let hitMin: TimeInterval = (windowStart == 20)
                ? firstWindowEnd + lead
                : windowStart + 2
            let hitMax = windowEnd - 2
            if hitMax > hitMin {
                let count = (windowStart == 20) ? particlesPerTwentySeconds / 2 : particlesPerTwentySeconds
                for _ in 0 ..< count {
                    let hitAt = TimeInterval.random(in: hitMin ..< hitMax)
                    let instrument = Instrument.allCases.randomElement()!
                    segments.append(InstrumentHitSegment(hitAtSeconds: hitAt, instrument: instrument, excludeFromScore: false))
                }
            }
            windowStart += 20
        }
        return segments.sorted { $0.hitAtSeconds < $1.hitAtSeconds }
    }

    private static let tapZoneWidth: CGFloat = 60
    /// Margin from right edge to tap zone (pt)
    private static let tapZoneRightMargin: CGFloat = 80

    /// Normalize meter (-36…0 dB) to 0…1
    private func normalizedLevel() -> Double {
        guard let player = audioPlayer, player.isPlaying else { return 0 }
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)
        let normalized = Double(power + 36) / 36.0
        return max(0, min(1, normalized))
    }

    /// Segment color at current time (black if none)
    private func color(for time: TimeInterval) -> UIColor {
        Self.colorSegments.first { $0.contains(time) }?.color ?? UIColor.black
    }

    /// Complement of background on color wheel (e.g. green→pink); also used for fireworks
    private func complementColor(of uiColor: UIColor) -> Color {
        let (color, _) = complementColorAndHue(of: uiColor)
        return color
    }

    /// Complement color and hue (for firework particles)
    private func complementColorAndHue(of uiColor: UIColor) -> (Color, hue: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                return (Color(red: 1 - r, green: 1 - g, blue: 1 - b), 0.5)
            }
            return (Color.white, 0.5)
        }
        let complementHue = (Double(h) + 0.5).truncatingRemainder(dividingBy: 1.0)
        let sat = min(1.0, Double(s) * 0.4 + 0.75)
        return (Color(hue: complementHue, saturation: sat, brightness: 1.0), complementHue)
    }

    /// Onboarding text for current time (nil if none)
    private func text(for time: TimeInterval) -> String? {
        Self.textSegments.first { $0.contains(time) }?.title
    }

    /// Music-box style gold rays at hit position
    private func makeHitFirework(explodeAt: CGPoint, color: Color, baseHue: Double, type: HitFireworkType) -> HitFirework {
        let screenH = UIScreen.main.bounds.height
        let launchFrom = CGPoint(x: explodeAt.x, y: screenH)
        let numRays = 48
        let baseRadius = Double.random(in: 220 ... 420)
        let goldColors: [Color] = [
            Color(red: 0.88, green: 0.72, blue: 0.35),
            Color(red: 0.78, green: 0.58, blue: 0.22),
            Color(red: 0.68, green: 0.52, blue: 0.2)
        ]
        let particles: [HitFireworkParticle] = (0 ..< numRays).map { i in
            let angle = Double(i) / Double(numRays) * 2 * .pi + Double.random(in: -0.02 ... 0.02)
            let rayColor = goldColors.randomElement()!
            return HitFireworkParticle(
                angle: angle,
                hue: 0.12,
                saturation: 0.6,
                brightness: 0.9,
                color: rayColor,
                size: Double.random(in: 2.0 ... 3.2),
                opacity: Double.random(in: 0.75 ... 1.0),
                t: Double(i) / Double(numRays)
            )
        }
        return HitFirework(
            launchFrom: launchFrom,
            explodeTo: explodeAt,
            color: Color(red: 0.82, green: 0.65, blue: 0.28),
            launchStart: Date(),
            type: type,
            particles: particles,
            baseRadius: baseRadius
        )
    }

    /// Restart track from the beginning
    private func restartTrack() {
        hitNumber = 0
        judgedSegmentIDs = []
        fireworks = []
        endSubtitleVisible = false
        endSubtitleScheduled = false
        audioPlayer?.currentTime = 0
        audioPlayer?.volume = Self.volumeGain(forHitNumber: 0)
        audioPlayer?.play()
    }

    /// Play short hit sound per instrument (WAV if available, else system sound)
    private func playHitSound(instrument: Instrument) {
        let player: AVAudioPlayer?
        switch instrument {
        case .triangle: player = hitSoundTriangle
        case .treeChime: player = hitSoundTreeChime
        case .cowbell: player = hitSoundCowbell
        }
        if let p = player {
            p.currentTime = 0
            p.play()
        } else {
            let sid: SystemSoundID
            switch instrument {
            case .triangle: sid = 1103
            case .treeChime: sid = 1104
            case .cowbell: sid = 1105
            }
            AudioServicesPlaySystemSound(sid)
        }
    }

    /// Hit judgment when circle is tapped. Hit if time is within ±hitWindowSeconds of note; each note judged once.
    private func judgeSegment(_ segment: InstrumentHitSegment) -> Bool {
        guard !judgedSegmentIDs.contains(segment.id) else { return false }
        let t = audioPlayer?.currentTime ?? 0
        let isHit = abs(t - segment.hitAtSeconds) <= InstrumentHitSegment.hitWindowSeconds

        judgedSegmentIDs.insert(segment.id)

        if isHit {
            if !segment.excludeFromScore {
                hitNumber += 1
                audioPlayer?.volume = Self.volumeGain(forHitNumber: hitNumber)
            }
            playHitSound(instrument: segment.instrument)
            let style: UIImpactFeedbackGenerator.FeedbackStyle = switch segment.instrument {
            case .triangle: .light
            case .treeChime: .heavy
            case .cowbell: .medium
            }
            let impact = UIImpactFeedbackGenerator(style: style)
            let intensity = segment.instrument.hapticIntensityBase * CGFloat(0.7 + 0.3 * hitProgress())
            impact.impactOccurred(intensity: min(1, intensity))
        }
        return isHit
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 0.1)) { _ in
                let currentTime = audioPlayer?.currentTime ?? 0
                MainTimelineContent(
                currentTime: currentTime,
                level: normalizedLevel(),
                segmentColor: color(for: currentTime),
                centerText: text(for: currentTime),
                hitNumber: hitNumber,
                endSubtitleVisible: endSubtitleVisible,
                judgedSegmentIDs: $judgedSegmentIDs,
                instrumentSegments: instrumentSegments,
                fireworks: $fireworks,
                hitProgress: hitProgress(),
                totalSegmentCount: Self.totalSegmentCount,
                tapZoneWidth: Self.tapZoneWidth,
                tapZoneRightMargin: Self.tapZoneRightMargin,
                pressingNeedle: pressingNeedle,
                showHitFeedback: showHitFeedback,
                onRestart: restartTrack,
                onVanish: { print("Vanish") },
                onSegmentTap: { segment, hitX, hitY, segColor in
                    let wasHit = judgeSegment(segment)
                    if wasHit {
                        showHitFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            showHitFeedback = false
                        }
                        pressingNeedle = segment.instrument
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            pressingNeedle = nil
                        }
                        let (sparkleColor, baseHue) = complementColorAndHue(of: segColor)
                        let firework = makeHitFirework(explodeAt: CGPoint(x: hitX, y: hitY), color: sparkleColor, baseHue: baseHue, type: .normal)
                        var next = fireworks
                        if next.count >= 8 { next.removeFirst() }
                        next.append(firework)
                        fireworks = next
                    }
                },
                onTrackEndChange: { newTime in
                    if newTime >= Self.trackDuration {
                        if !endSubtitleScheduled {
                            endSubtitleScheduled = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                endSubtitleVisible = true
                            }
                        }
                    } else {
                        endSubtitleVisible = false
                        endSubtitleScheduled = false
                    }
                },
                onLevelPulse: {
                    guard audioPlayer?.isPlaying == true else { return }
                    let l = normalizedLevel()
                    if l > 0.08 {
                        let g = UIImpactFeedbackGenerator(style: .soft)
                        g.impactOccurred(intensity: min(1, l * 1.3))
                    }
                }
                )
            }
            .ignoresSafeArea()

            MusicBoxLidView(isOpen: lidOpen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(!lidOpen)
        }
        .onAppear {
            if instrumentSegments.isEmpty {
                instrumentSegments = Self.makeInstrumentSegments()
            }
            hitSoundTriangle = Self.loadHitSoundPlayer(for: .triangle)
            hitSoundTreeChime = Self.loadHitSoundPlayer(for: .treeChime)
            hitSoundCowbell = Self.loadHitSoundPlayer(for: .cowbell)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 1.15)) {
                    lidOpen = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 1.15) {
                playLaPrimavera()
            }
        }
    }
}

// MARK: - Lid opening animation (double doors) on launch
private struct MusicBoxLidView: View {
    let isOpen: Bool

    private static let lidDuration: Double = 1.15
    private static let goldTrim = Color(red: 0.82, green: 0.66, blue: 0.28)
    private static let goldDark = Color(red: 0.55, green: 0.42, blue: 0.15)
    private static let woodDark = Color(red: 0.18, green: 0.12, blue: 0.08)
    private static let woodMid = Color(red: 0.32, green: 0.22, blue: 0.14)
    private static let woodLight = Color(red: 0.42, green: 0.3, blue: 0.18)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                HStack(spacing: 0) {
                    lidPanel(isLeft: true, width: w / 2, height: h)
                    lidPanel(isLeft: false, width: w / 2, height: h)
                }
                .frame(width: w, height: h)
                if !isOpen {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Self.goldDark, Self.goldTrim.opacity(0.9), Self.goldDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: h)
                        .position(x: w / 2, y: h / 2)
                }
            }
            .frame(width: w, height: h)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isOpen ? 0 : 1)
        .animation(.easeOut(duration: Self.lidDuration), value: isOpen)
    }

    private func lidPanel(isLeft: Bool, width: CGFloat, height: CGFloat) -> some View {
        // Double doors: left opens left, right opens right (outward)
        let openAngle: Double = isOpen ? (isLeft ? -92 : 92) : 0
        return ZStack {
            LinearGradient(
                colors: [Self.woodDark, Self.woodMid, Self.woodLight, Self.woodMid],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Self.goldTrim.opacity(0.5))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Self.goldTrim, Self.goldDark.opacity(0.8), Self.goldTrim],
                            startPoint: isLeft ? .leading : .trailing,
                            endPoint: isLeft ? .trailing : .leading
                        ),
                        lineWidth: 4
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(Self.goldTrim.opacity(0.6), lineWidth: 1)
                    .padding(8)
            }
            VStack(spacing: 0) {
                ForEach(0 ..< 8, id: \.self) { _ in
                    Spacer(minLength: 0)
                    if isLeft {
                        Circle().fill(Self.goldTrim.opacity(0.25)).frame(width: 3, height: 3)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 20)
                    } else {
                        Circle().fill(Self.goldTrim.opacity(0.25)).frame(width: 3, height: 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
        }
        .frame(width: width, height: height)
        .rotation3DEffect(
            .degrees(openAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: isLeft ? .trailing : .leading,
            perspective: 0.4
        )
        .animation(.easeOut(duration: Self.lidDuration), value: isOpen)
    }
}

// MARK: - Main timeline content (reduces body type inference)
private struct MainTimelineContent: View {
    let currentTime: TimeInterval
    let level: Double
    let segmentColor: UIColor
    let centerText: String?
    let hitNumber: Int
    let endSubtitleVisible: Bool
    @Binding var judgedSegmentIDs: Set<UUID>
    let instrumentSegments: [InstrumentHitSegment]
    @Binding var fireworks: [HitFirework]
    let hitProgress: Double
    let totalSegmentCount: Int
    let tapZoneWidth: CGFloat
    let tapZoneRightMargin: CGFloat
    let pressingNeedle: Instrument?
    let showHitFeedback: Bool
    let onRestart: () -> Void
    let onVanish: () -> Void
    let onSegmentTap: (InstrumentHitSegment, CGFloat, CGFloat, UIColor) -> Void
    let onTrackEndChange: (TimeInterval) -> Void
    let onLevelPulse: () -> Void

    private var trackDuration: TimeInterval { 99 }
    private var isTrackEnded: Bool { currentTime >= trackDuration }
    /// Gold text color (unified for all text)
    private static let goldText = Color(red: 0.88, green: 0.70, blue: 0.22)
    private var goldTextColor: Color { Self.goldText }
    private var textColor: Color { goldTextColor }
    private var messageToShow: String? {
        isTrackEnded ? "This is your music." : centerText
    }
    private var isOnboardingMessage: Bool { centerText != nil && !isTrackEnded }

    var body: some View {
        let bg = ZStack {
            Color(red: 0.10, green: 0.09, blue: 0.08)
            Color(uiColor: segmentColor).opacity(min(1.0, level * 1.75))
            Color(red: 0.18, green: 0.15, blue: 0.12)
                .opacity(0.5 + hitProgress * 0.1)
            Color.white.opacity(level * 0.22)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()

        return ZStack {
            bg

            musicBoxInteriorOverlay

            Color(red: 0.18, green: 0.16, blue: 0.14)
                .opacity(0.5 + hitProgress * 0.06)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                center: .center,
                startRadius: 80,
                endRadius: 400
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            centralGlowOverlay(level: level)

            vignetteOverlay

            glassLidReflectionOverlay

            if let title = messageToShow {
                messageBlock(title: title)
            }

            GeometryReader { geo in
                tapZone(geo: geo, hitProgress: hitProgress, pressingNeedle: pressingNeedle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { FrameBorderView(intensity: hitProgress) }
        .overlay { fireworksOverlay }
        .overlay {
            if showHitFeedback {
                Text("Hit!")
                    .font(.system(.title2, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundStyle(goldTextColor)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.96, green: 0.9, blue: 0.75).opacity(0.98))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .accessibilityLabel("Hit. You can feel it with haptics too.")
            }
        }
        .overlay {
            GeometryReader { geo in
                let top = geo.safeAreaInsets.top
                let bottom = geo.safeAreaInsets.bottom
                ZStack(alignment: .top) {
                    if !isTrackEnded {
                        Text("\(hitNumber) / \(totalSegmentCount)")
                            .font(.system(.title2, design: .serif))
                            .fontWeight(.semibold)
                            .foregroundStyle(goldTextColor)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity)
                            .padding(.top, top + 8)
                    }
                    VStack {
                        Spacer(minLength: 0)
                        Text("You can play even without sound: feel the vibration and watch for \"Hit!\" on screen.")
                            .font(.system(.caption2, design: .serif))
                            .foregroundStyle(goldTextColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.6))
                            .padding(.bottom, bottom + 8)
                            .accessibilityLabel("For those who are deaf or hard of hearing: hits are indicated by vibration and a \"Hit!\" message.")
                    }
                }
            }
            .allowsHitTesting(false)
            .zIndex(1000)
        }
        .animation(.easeOut(duration: 0.25), value: showHitFeedback)
        .animation(.easeOut(duration: 0.04), value: level)
        .animation(.easeOut(duration: 0.04), value: currentTime)
        .animation(.easeOut(duration: 0.25), value: hitNumber)
        .onChange(of: Int(currentTime / 0.2)) { _, _ in onLevelPulse() }
        .onChange(of: currentTime) { _, newTime in onTrackEndChange(newTime) }
    }

    @ViewBuilder
    private func messageBlock(title: String) -> some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(.title2, design: .serif))
                .fontWeight(.medium)
                .foregroundStyle(goldTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if isTrackEnded {
                if endSubtitleVisible {
                    Text("The sound of spring starts here again.")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(goldTextColor.opacity(0.9))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                Text("Score")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(goldTextColor)
                Text("\(hitNumber) / \(totalSegmentCount)")
                    .font(.system(.title3, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundStyle(goldTextColor)
                if hitNumber >= totalSegmentCount {
                    Text("Every note, perfectly played.")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(goldTextColor)
                }
                Button(action: onRestart) {
                    Text("Play again")
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.medium)
                        .foregroundStyle(goldTextColor)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.45, green: 0.28, blue: 0.22))
                        .clipShape(Capsule())
                }
                .padding(.top, 12)
            }
        }
        .animation(.easeOut(duration: isOnboardingMessage ? 0.65 : 0.15), value: messageToShow)
        .animation(.easeOut(duration: 0.9), value: endSubtitleVisible)
    }

    private func tapZone(geo: GeometryProxy, hitProgress: Double, pressingNeedle: Instrument?) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let zoneGold = Color(red: 0.72, green: 0.55, blue: 0.25)
        let zoneFillOpacity = 0.22 + hitProgress * 0.12
        let zoneStrokeOpacity = 0.35 + hitProgress * 0.45
        return ZStack(alignment: .leading) {
            HStack {
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(zoneGold.opacity(zoneFillOpacity))
                        .frame(width: tapZoneWidth)
                        .frame(maxHeight: .infinity)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(zoneGold.opacity(zoneStrokeOpacity), lineWidth: 2)
                        .frame(width: tapZoneWidth)
                        .frame(maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .accessibilityLabel("Hit zone")
                .accessibilityHint("Tap the moving circle when it is between the lines; you’ll feel a vibration and see \"Hit!\". Works without sound.")
                Spacer().frame(width: tapZoneRightMargin)
            }
            needlePinsView(w: w, h: h, pressingNeedle: pressingNeedle)
            ForEach(instrumentSegments.filter { $0.isVisible(at: currentTime) && !judgedSegmentIDs.contains($0.id) }) { segment in
                let hitX = w - tapZoneWidth / 2 - tapZoneRightMargin + segment.buttonX(at: currentTime)
                let hitY = h / 2 + segment.instrument.laneOffsetY
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                segment.instrument.particleColor.opacity(0.95),
                                segment.instrument.particleColor,
                                segment.instrument.particleColor.opacity(0.85)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 28
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(zoneGold.opacity(0.3 + hitProgress * 0.5), lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            .blur(radius: 0.5)
                            .offset(x: -1, y: -1)
                    )
                    .contentShape(Circle())
                    .position(x: hitX, y: hitY)
                    .accessibilityLabel("\(segment.instrument.accessibleName). Tap to hit; vibration and on-screen feedback.")
                    .accessibilityHint("Tap when the circle is between the lines.")
                    .onTapGesture {
                        onSegmentTap(segment, hitX, hitY, segmentColor)
                    }
            }
        }
        .overlay(alignment: .trailing) {
            combRidgeView(geo: geo)
        }
        .background(
            VanishCheckView(
                currentTime: currentTime,
                segments: instrumentSegments,
                judgedSegmentIDs: $judgedSegmentIDs,
                onVanish: onVanish
            )
        )
    }

    private func needlePinsView(w: CGFloat, h: CGFloat, pressingNeedle: Instrument?) -> some View {
        let needleX = w - tapZoneWidth / 2 - tapZoneRightMargin
        let needleWidth: CGFloat = 10
        let needleHeight: CGFloat = 36
        let pressOffset: CGFloat = 14
        let brassNeedle = Color(red: 0.65, green: 0.5, blue: 0.28)
        let brassHighlight = Color(red: 0.82, green: 0.7, blue: 0.45)
        return ZStack(alignment: .top) {
            ForEach(Instrument.allCases, id: \.id) { instrument in
                let laneY = h / 2 + instrument.laneOffsetY
                let isPressing = pressingNeedle == instrument
                let needleTopY = laneY - needleHeight
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [brassHighlight.opacity(0.9), brassNeedle, brassNeedle.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: needleWidth, height: needleHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(brassHighlight.opacity(0.4), lineWidth: 1)
                    )
                    .position(x: needleX, y: needleTopY + needleHeight / 2 + (isPressing ? pressOffset : 0))
                    .animation(isPressing ? .easeOut(duration: 0.06) : .spring(response: 0.28, dampingFraction: 0.72), value: isPressing)
            }
        }
        .allowsHitTesting(false)
    }

    private func combRidgeView(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.4, blue: 0.28).opacity(0.2),
                            Color(red: 0.6, green: 0.48, blue: 0.3).opacity(0.35),
                            Color(red: 0.5, green: 0.4, blue: 0.28).opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 6)
                .frame(maxHeight: .infinity)
            Spacer().frame(width: tapZoneRightMargin + tapZoneWidth - 2)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var fireworksOverlay: some View {
        ForEach(fireworks) { fw in
            HitFireworkView(firework: fw) {
                fireworks.removeAll { $0.id == fw.id }
            }
        }
        .allowsHitTesting(false)
    }

    private func centralGlowOverlay(level: Double) -> some View {
        RadialGradient(
            colors: [
                Color.white.opacity(0.05 * level),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var musicBoxInteriorOverlay: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color(red: 0.4, green: 0.32, blue: 0.28).opacity(0.08)
                    ],
                    center: .center,
                    startRadius: 120,
                    endRadius: 340
                )
            )
            .frame(width: 520, height: 700)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    private var glassLidReflectionOverlay: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.07),
                Color.white.opacity(0.02),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var vignetteOverlay: some View {
        let vignetteStrength = 0.38 * (1 - hitProgress * 0.55)
        return ZStack {
            Color.clear
            RadialGradient(
                colors: [.clear, Color.black.opacity(vignetteStrength)],
                center: .center,
                startRadius: 160 + hitProgress * 60,
                endRadius: 480 + hitProgress * 80
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Brass-colored frame edge; intensity (0…1) varies with hitProgress
private struct FrameBorderView: View {
    let intensity: Double

    private static let edgeWidth: CGFloat = 80
    private static let brassColor = Color(red: 0.76, green: 0.58, blue: 0.28)
    private static let brassHighlight = Color(red: 0.88, green: 0.75, blue: 0.45)
    private static let shadowColor = Color(red: 0.25, green: 0.2, blue: 0.15)

    var body: some View {
        let t = min(1, max(0, intensity))
        let edgeOpacity = 0.12 + 0.55 * t
        let edgeColor = Self.brassColor.opacity(edgeOpacity)
        let innerOpacity = 0.08 + 0.25 * t
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Self.shadowColor.opacity(0.2), edgeColor, Self.brassHighlight.opacity(edgeOpacity * 0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.edgeWidth)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Self.brassHighlight.opacity(edgeOpacity * 0.3), edgeColor, Self.shadowColor.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.edgeWidth)
            }
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Self.shadowColor.opacity(0.2), edgeColor, Self.brassHighlight.opacity(edgeOpacity * 0.4)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.edgeWidth)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Self.brassHighlight.opacity(edgeOpacity * 0.3), edgeColor, Self.shadowColor.opacity(0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.edgeWidth)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Self.brassColor.opacity(innerOpacity), lineWidth: 1.5)
                .padding(Self.edgeWidth - 10)
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.25), value: intensity)
    }
}

// MARK: - Music-box style spark (gold rays)

private enum HitFireworkPhase {
    case launching
    case exploding
    case finished
}

private enum HitFireworkType {
    case normal
    case shidare
    case split
}

private struct HitFireworkParticle {
    let angle: Double
    let hue: Double
    let saturation: Double
    let brightness: Double
    let color: Color
    let size: Double
    let opacity: Double
    let t: Double
}

private struct HitFirework: Identifiable {
    let id = UUID()
    let launchFrom: CGPoint
    let explodeTo: CGPoint
    let color: Color
    let launchStart: Date
    let type: HitFireworkType
    let particles: [HitFireworkParticle]
    let baseRadius: Double
}

private struct HitFireworkParticleView: View {
    let particle: HitFireworkParticle
    let type: HitFireworkType
    let center: CGPoint
    let progress: Double
    let baseRadius: Double

    var body: some View {
        let angle = particle.angle
        let length = progress * baseRadius * (1 - progress * 0.4)
        let lineWidth = max(1.2, particle.size * (1 - progress * 0.7))
        let fade = pow(max(0, 1 - progress), 1.2)
        let baseOpacity = fade * particle.opacity
        let start = center
        let end = CGPoint(
            x: center.x + CGFloat(cos(angle) * length),
            y: center.y + CGFloat(sin(angle) * length)
        )
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            LinearGradient(
                colors: [
                    particle.color.opacity(baseOpacity),
                    particle.color.opacity(baseOpacity * 0.4)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

private struct HitFireworkView: View {
    @State private var phase: HitFireworkPhase
    @State private var explodeStart: Date?
    let firework: HitFirework
    let onFinished: () -> Void

    init(firework: HitFirework, onFinished: @escaping () -> Void) {
        self.firework = firework
        self.onFinished = onFinished
        _phase = State(initialValue: HitFireworkPhase.launching)
        _explodeStart = State(initialValue: nil as Date?)
    }

    private static let explodeDuration: TimeInterval = 1.0

    var body: some View {
        TimelineView(.animation) { _ in
            let now = Date()
            let _ = {
                DispatchQueue.main.async {
                    if phase == .launching {
                        phase = .exploding
                        explodeStart = now
                        triggerFireworkVibration()
                    } else if phase == .exploding, let start = explodeStart, now.timeIntervalSince(start) > Self.explodeDuration {
                        phase = .finished
                        onFinished()
                    }
                }
                return ()
            }()
            ZStack {
                if phase == .exploding, let start = explodeStart {
                    let elapsed = min(now.timeIntervalSince(start), Self.explodeDuration)
                    let progress = elapsed / Self.explodeDuration
                    ForEach(Array(firework.particles.enumerated()), id: \.offset) { _, p in
                        HitFireworkParticleView(
                            particle: p,
                            type: firework.type,
                            center: firework.explodeTo,
                            progress: progress,
                            baseRadius: firework.baseRadius
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private func triggerFireworkVibration() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Marks notes as vanished when they pass through without being tapped
private struct VanishCheckView: View {
    let currentTime: TimeInterval
    let segments: [InstrumentHitSegment]
    @Binding var judgedSegmentIDs: Set<UUID>
    var onVanish: (() -> Void)?

    var body: some View {
        Color.clear
            .onChange(of: currentTime) { _, newTime in
                var didVanish = false
                for segment in segments {
                    if newTime >= segment.visibleEndSeconds, !judgedSegmentIDs.contains(segment.id) {
                        judgedSegmentIDs = judgedSegmentIDs.union([segment.id])
                        didVanish = true
                    }
                }
                if didVanish {
                    onVanish?()
                }
            }
    }
}

private extension ContentView {
    func playLaPrimavera() {
        guard let url = Bundle.main.url(forResource: "LaPrimavera", withExtension: "wav", subdirectory: "Assets")
            ?? Bundle.main.url(forResource: "LaPrimavera", withExtension: "wav") else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.isMeteringEnabled = true
            player.volume = Self.volumeGain(forHitNumber: 0)
            audioPlayer = player
            player.play()
        } catch {
            // If playback failed
        }
    }

    static func loadHitSoundPlayer(for instrument: Instrument) -> AVAudioPlayer? {
        let name: String
        switch instrument {
        case .triangle: name = "triangle"
        case .treeChime: name = "treeChime"
        case .cowbell: name = "cowbell"
        }
        let url = Bundle.main.url(forResource: "Hit_\(name)", withExtension: "wav", subdirectory: "Assets")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Assets")
            ?? Bundle.main.url(forResource: "Hit_\(name)", withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: "Hit_\(name)", withExtension: "mp3", subdirectory: "Assets")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Assets")
            ?? Bundle.main.url(forResource: "Hit_\(name)", withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
        guard let url = url else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        return player
    }
}
