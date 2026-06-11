import SwiftUI

/// A titled slate column (e.g. PENDING / CONVERTED) holding a scrollable list of job rows.
struct SlateColumn<Row: View>: View {
    let title: String
    let count: Int
    let systemImage: String
    let emptyText: String
    let isEmpty: Bool
    var accessory: AnyView? = nil
    @ViewBuilder let rows: () -> Row

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: systemImage)
                Slate.label(title)
                if let accessory {
                    accessory
                }
                Spacer()
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Slate.chalk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Slate.bg, in: Capsule())
            }
            .foregroundStyle(Slate.chalkDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(Slate.panelEdge).frame(height: 1)

            if isEmpty {
                Spacer()
                Text(emptyText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Slate.chalkDim)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        rows()
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Slate.panel.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Slate.panelEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A pending job row: name, status, channel override, and progress while active.
struct PendingSlateRow: View {
    @Bindable var job: ConversionJob
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(job.displayName)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Slate.chalk)
                    .lineLimit(1)
                Spacer()
                if !job.status.isActive {
                    Menu {
                        Picker("LTC Channel", selection: $job.channelSelection) {
                            Text("Auto-detect").tag(LTCChannelSelection.auto)
                            Text("Left channel").tag(LTCChannelSelection.left)
                            Text("Right channel").tag(LTCChannelSelection.right)
                        }
                        Button(role: .destructive, action: onRemove) {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Slate.chalkDim)
                    }
                }
            }
            Text(statusText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Slate.chalkDim)
                .lineLimit(2)
            if job.status.isActive {
                ProgressView(value: job.progress).tint(Slate.accent)
            }
        }
        .padding(10)
        .background(Slate.bg)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Slate.panelEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        switch job.status {
        case .queued: return "QUEUED · CH \(channelLabel)"
        case .decoding: return "DECODING LTC…"
        case .writing: return "WRITING TC… \(Int(job.progress * 100))%"
        case .finished: return "DONE"
        case .failed(let m): return "FAILED · \(m)"
        }
    }
    private var channelLabel: String {
        switch job.channelSelection {
        case .auto: return "AUTO"; case .left: return "L"; case .right: return "R"
        }
    }
    private var icon: String {
        switch job.status {
        case .queued: return "clock"
        case .decoding: return "waveform.badge.magnifyingglass"
        case .writing: return "timecode"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    private var iconColor: Color {
        switch job.status {
        case .failed: return Slate.warn
        case .finished: return Slate.done
        default: return Slate.accent
        }
    }
}

/// A converted job row: name, recovered start timecode + rate, and export.
struct ConvertedSlateRow: View {
    let job: ConversionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Slate.done)
                Text(job.displayName)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Slate.chalk)
                    .lineLimit(1)
                Spacer()
                if case .finished(let url, _, _) = job.status {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Slate.accent)
                    }
                }
            }
            if case .finished(_, let tc, let rate) = job.status {
                HStack(spacing: 10) {
                    Text(tc.displayString)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(Slate.chalk)
                    Text(rate.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Slate.chalkDim)
                    if let ch = job.resolvedLTCChannel {
                        Text("LTC \(ch == 0 ? "L" : "R")")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Slate.chalkDim)
                    }
                }
            }
        }
        .padding(10)
        .background(Slate.bg)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Slate.done.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
