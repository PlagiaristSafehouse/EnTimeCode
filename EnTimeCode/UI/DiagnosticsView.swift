import SwiftUI

/// Shows the current and previous session breadcrumb logs, with copy/share so the trail can be
/// reported even when device crash logs aren't available.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    private let diag = Diagnostics.shared

    var body: some View {
        NavigationStack {
            List {
                if diag.previousSessionCrashed {
                    Section {
                        Label("The previous session ended unexpectedly while converting. The log below shows how far it got.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !diag.previousSession.isEmpty {
                    Section("Previous Session") {
                        ForEach(Array(diag.previousSession.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                Section("Current Session") {
                    ForEach(Array(diag.entries.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: fullText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var fullText: String {
        """
        === PREVIOUS SESSION ===
        \(diag.previousSessionText)

        === CURRENT SESSION ===
        \(diag.entries.joined(separator: "\n"))
        """
    }
}
