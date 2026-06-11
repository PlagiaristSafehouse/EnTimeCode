import SwiftUI

/// Visual theme for the clapperboard / film-slate UI.
enum Slate {
    static let bg = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.14, green: 0.15, blue: 0.18)
    static let panelEdge = Color.white.opacity(0.12)
    static let chalk = Color(red: 0.93, green: 0.95, blue: 0.96)
    static let chalkDim = Color.white.opacity(0.55)
    static let accent = Color(red: 0.16, green: 0.55, blue: 0.92)
    static let done = Color(red: 0.30, green: 0.78, blue: 0.50)
    static let warn = Color(red: 0.95, green: 0.62, blue: 0.25)

    static func label(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.bold))
            .tracking(1.5)
            .foregroundStyle(chalkDim)
    }
}

/// The diagonal black/white striped bar of a clapperboard's hinged stick.
/// The stripes scroll continuously — slowly when idle, faster while `active` — and the optional
/// `reversed` flag sends the travel the other way (so top/bottom bars move oppositely).
struct ClapperStripes: View {
    var active: Bool = false
    var reversed: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !active || scenePhase != .active)) { timeline in
            Canvas { ctx, size in
                guard size.width > 0, size.height > 0 else { return }
                let stripeW = size.height * 0.85
                let skew = size.height * 0.55
                let period = stripeW * 2

                let speed: Double = 120 // points per second, only while converting
                let t = timeline.date.timeIntervalSinceReferenceDate
                var phase = active ? CGFloat((t * speed).truncatingRemainder(dividingBy: Double(period))) : 0
                if reversed { phase = period - phase }

                var x = -skew - period - phase
                var i = 0
                while x < size.width + skew + period {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + stripeW, y: 0))
                    path.addLine(to: CGPoint(x: x + stripeW - skew, y: size.height))
                    path.addLine(to: CGPoint(x: x - skew, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(i % 2 == 0 ? .black : Slate.chalk))
                    x += stripeW
                    i += 1
                }
            }
        }
        .drawingGroup()
    }
}

/// A labeled slate field box (LABEL above value), like the writable cells on a real slate.
struct SlateField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Slate.label(label)
            content
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(Slate.chalk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Slate.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Slate.panelEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The slate "timebar": a film-perforated progress bar showing batch progress.
struct SlateTimebar: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Slate.label("TIMECODE PROGRESS")
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Slate.chalk)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Slate.panel)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Slate.panelEdge, lineWidth: 1))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [Slate.accent, Slate.done],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                    // Film perforations overlay.
                    HStack(spacing: 10) {
                        ForEach(0..<40, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.black.opacity(0.18))
                                .frame(width: 4, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            }
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.25), value: progress)
        }
    }
}
