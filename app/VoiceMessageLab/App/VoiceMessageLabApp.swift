import SwiftUI

@main
struct VoiceMessageLabApp: App {
    @State private var model: VoiceMessageLabModel

    init() {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        _model = State(initialValue: VoiceMessageLabModel(
            recorder: VoiceRecorder(),
            store: LocalVoiceMessageStore(directory: directory),
            transcriber: ParakeetVoiceTranscriber()
        ))
    }

    var body: some Scene {
        WindowGroup {
            VoiceMessageLabScreen(model: model)
        }
    }
}
