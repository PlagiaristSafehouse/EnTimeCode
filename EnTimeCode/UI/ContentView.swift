import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(BatchProcessor.self) private var batch

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importError: String?
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            Slate.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ClapperStripes(active: batch.isRunning).frame(height: 40)

                slateHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                columns
                    .padding(.horizontal, 16)

                SlateTimebar(progress: batch.overallProgress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                ClapperStripes(active: batch.isRunning, reversed: true).frame(height: 26)
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
                      allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoItems,
                      matching: .videos,
                      photoLibrary: .shared())
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadPhotoItems(newItems) }
        }
        .alert("Import Failed",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    // MARK: Slate header

    private var slateHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "timecode")
                Text("EnTimeCode")
                    .font(.system(.title3, design: .monospaced).weight(.heavy))
                    .tracking(1)
            }
            .foregroundStyle(Slate.chalk)

            Spacer(minLength: 8)

            SlateField("ROLL") { Text(rollText) }.frame(maxWidth: 130)
            SlateField("DONE") { Text("\(batch.convertedJobs.count)") }.frame(maxWidth: 90)

            Menu {
                Button { showFileImporter = true } label: { Label("From Files", systemImage: "folder") }
                Button { showPhotoPicker = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
            } label: {
                slateIcon("plus", tint: Slate.accent)
            }

            if !batch.convertedJobs.isEmpty {
                Button { batch.clearFinished() } label: { slateIcon("tray.and.arrow.up") }
            }

            Button { showDiagnostics = true } label: {
                slateIcon(Diagnostics.shared.previousSessionCrashed ? "exclamationmark.triangle.fill" : "ladybug",
                          tint: Diagnostics.shared.previousSessionCrashed ? Slate.warn : Slate.chalkDim)
            }
        }
    }

    /// Import menu (Files / Photos). `compact` renders a small inline "+" for column headers.
    private func importMenu(compact: Bool = false) -> some View {
        Menu {
            Button { showFileImporter = true } label: { Label("From Files", systemImage: "folder") }
            Button { showPhotoPicker = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
        } label: {
            if compact {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Slate.accent)
            } else {
                slateIcon("plus", tint: Slate.accent)
            }
        }
    }

    private func slateIcon(_ name: String, tint: Color = Slate.chalk) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Slate.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Slate.panelEdge, lineWidth: 1))
    }

    private var rollText: String {
        batch.jobs.isEmpty ? "—" : "\(batch.jobs.count) CLIP\(batch.jobs.count == 1 ? "" : "S")"
    }

    // MARK: Columns + center button

    private var columns: some View {
        HStack(spacing: 14) {
            SlateColumn(title: "PENDING",
                        count: batch.pendingJobs.count,
                        systemImage: "tray.full",
                        emptyText: "No clips queued.\nTap ＋ to import videos\nwith LTC audio.",
                        isEmpty: batch.pendingJobs.isEmpty,
                        accessory: AnyView(importMenu(compact: true))) {
                ForEach(batch.pendingJobs) { job in
                    PendingSlateRow(job: job) { batch.remove(job) }
                }
            }

            ClapperButton(isRunning: batch.isRunning,
                          pendingCount: batch.pendingCount,
                          progress: batch.overallProgress,
                          onStart: { batch.start() },
                          onStop: { batch.cancel() })

            SlateColumn(title: "CONVERTED",
                        count: batch.convertedJobs.count,
                        systemImage: "checkmark.seal",
                        emptyText: "Converted clips with\nembedded timecode\nappear here.",
                        isEmpty: batch.convertedJobs.isEmpty) {
                ForEach(batch.convertedJobs) { job in
                    ConvertedSlateRow(job: job)
                }
            }
        }
    }

    // MARK: Import handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let ok = url.startAccessingSecurityScopedResource()
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                Diagnostics.shared.log("IMPORT files url=\(url.lastPathComponent) scoped=\(ok) size=\(size)")
            }
            batch.add(urls)
        case .failure(let error):
            Diagnostics.shared.log("IMPORT files FAILED \(error.localizedDescription)")
            importError = error.localizedDescription
        }
    }

    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        Diagnostics.shared.log("IMPORT photos count=\(items.count)")
        var urls: [URL] = []
        for item in items {
            do {
                if let movie = try await item.loadTransferable(type: MovieFile.self) {
                    let size = (try? movie.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    Diagnostics.shared.log("IMPORT photos loaded \(movie.url.lastPathComponent) size=\(size)")
                    urls.append(movie.url)
                } else {
                    Diagnostics.shared.log("IMPORT photos loadTransferable returned nil")
                }
            } catch {
                Diagnostics.shared.log("IMPORT photos FAILED \(error.localizedDescription)")
                importError = error.localizedDescription
            }
        }
        batch.add(urls)
        photoItems = []
    }
}
