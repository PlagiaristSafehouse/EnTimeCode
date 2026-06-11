import SwiftUI

/// The central clapper action: a round button that starts the batch ("ROLL") or stops it,
/// showing overall progress as a ring while running.
struct ClapperButton: View {
    let isRunning: Bool
    let pendingCount: Int
    let progress: Double
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: isRunning ? onStop : onStart) {
            ZStack {
                Circle()
                    .fill(Slate.panel)
                    .overlay(Circle().stroke(Slate.panelEdge, lineWidth: 2))

                if isRunning {
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, progress)))
                        .stroke(LinearGradient(colors: [Slate.accent, Slate.done],
                                               startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(8)
                        .animation(.easeInOut(duration: 0.25), value: progress)
                }

                VStack(spacing: 4) {
                    Image(systemName: isRunning ? "stop.fill" : "film.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(isRunning ? Slate.warn : Slate.accent)
                    Text(isRunning ? "STOP" : "ROLL")
                        .font(.system(.headline, design: .monospaced).weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(Slate.chalk)
                    if !isRunning {
                        Text(pendingCount > 0 ? "\(pendingCount) queued" : "no clips")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Slate.chalkDim)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 132, height: 132)
        .disabled(!isRunning && pendingCount == 0)
        .opacity(!isRunning && pendingCount == 0 ? 0.5 : 1)
    }
}
