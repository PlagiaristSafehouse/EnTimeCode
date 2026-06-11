import SwiftUI

@main
struct EnTimeCodeApp: App {
    @State private var batch: BatchProcessor

    init() {
        Diagnostics.shared.log("APP launch")
        let processor = BatchProcessor()
        processor.register()
        _batch = State(initialValue: processor)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(batch)
        }
    }
}
