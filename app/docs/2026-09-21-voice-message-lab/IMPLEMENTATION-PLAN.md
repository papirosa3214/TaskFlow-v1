# VoiceMessageLab Implementation Plan

> Исполнять по задачам: сначала красный тест, затем минимальная правка, затем проверка и отдельный коммит.

**Goal:** Build an installable, offline iPhone prototype for recording, playing, and locally transcribing voice messages.

**Architecture:** A separate `VoiceMessageLab` app target owns its UI and sandbox data. `VoiceRecorder` produces AAC `.m4a` files and metering data; a transcription adapter processes the finished file independently, so the audio message is visible before the text is ready.

**Tech Stack:** SwiftUI, AVFoundation, Observation, FluidAudio/Parakeet TDT v3, XCTest, XcodeGen.

**Дизайн:** [DESIGN.md](DESIGN.md)

## Global Constraints

- Deployment target is iOS 18.0; use only public Apple APIs and no Messages assets.
- Do not modify TaskFlow sources, server APIs, existing chat code, or `DictationEngine`.
- Audio is AAC `.m4a`; all first-stage data stays in the prototype sandbox.
- Transcript starts independently after recording completes and never prevents audio playback.
- Use test-first implementation; every new behavior must be observed failing before its production implementation exists.

---

## File Structure

- `project.yml`: app and test targets plus FluidAudio dependency.
- `VoiceMessageLab/App/VoiceMessageLabApp.swift`: app entry point and dependency wiring.
- `VoiceMessageLab/Domain/VoiceMessage.swift`: message and transcript states.
- `VoiceMessageLab/Domain/LocalVoiceMessageStore.swift`: persistence and restoration.
- `VoiceMessageLab/Audio/VoiceRecorder.swift`: microphone, `.m4a`, meter, cancellation.
- `VoiceMessageLab/Audio/VoicePlayer.swift`: exclusive local playback.
- `VoiceMessageLab/Transcription/VoiceTranscriber.swift`: Parakeet adapter.
- `VoiceMessageLab/Presentation/VoiceMessageLabModel.swift`: recording/transcription orchestration.
- `VoiceMessageLab/Presentation/VoiceMessageLabScreen.swift`: chat, composer, audio bubble.
- `VoiceMessageLabTests/*.swift`: isolated unit tests.

### Task 1: Create target and message contract

**Files:**
- Modify: `project.yml`
- Create: `VoiceMessageLab/App/VoiceMessageLabApp.swift`
- Create: `VoiceMessageLab/Domain/VoiceMessage.swift`
- Create: `VoiceMessageLabTests/VoiceMessageTests.swift`

**Produces:** `VoiceMessage(id: UUID, audioURL: URL, duration: TimeInterval, createdAt: Date, transcript: TranscriptState)`, where `TranscriptState` is `.pending`, `.ready(String)`, or `.failed`.

- [ ] Write the failing test:

```swift
func test_newVoiceMessage_startsWithPendingTranscript() {
    let message = VoiceMessage(audioURL: URL(fileURLWithPath: "/tmp/voice.m4a"), duration: 2)
    XCTAssertEqual(message.transcript, .pending)
}
```

- [ ] Run `xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -destination 'platform=iOS Simulator,id=ED3C7DF7-F895-45B6-8A28-F67C02362103' test`; expect a missing target/type failure.
- [ ] Add the target, its privacy string, and minimal `Codable, Equatable` domain model.
- [ ] Rerun the command; expect `VoiceMessageTests` green.
- [ ] Commit: `git add project.yml VoiceMessageLab VoiceMessageLabTests && git commit -m "feat: add voice message lab target"`.

### Task 2: Persist the local message history

**Files:**
- Create: `VoiceMessageLab/Domain/LocalVoiceMessageStore.swift`
- Create: `VoiceMessageLabTests/LocalVoiceMessageStoreTests.swift`

**Produces:** `init(directory: URL)`, `func load() throws -> [VoiceMessage]`, and `func save(_ messages: [VoiceMessage]) throws`.

- [ ] Write the failing test:

```swift
func test_saveThenLoad_restoresMessageAndTranscript() throws {
    let store = LocalVoiceMessageStore(directory: temporaryDirectory)
    try store.save([fixture(transcript: .ready("Привет"))])
    XCTAssertEqual(try store.load(), [fixture(transcript: .ready("Привет"))])
}
```

- [ ] Run `xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -only-testing:VoiceMessageLabTests/LocalVoiceMessageStoreTests test -destination 'generic/platform=iOS Simulator'`; expect a missing-store failure.
- [ ] Implement atomic `JSONEncoder` write and empty-array behavior when the index is absent.
- [ ] Rerun the command; expect green.
- [ ] Commit: `git add VoiceMessageLab/Domain VoiceMessageLabTests/LocalVoiceMessageStoreTests.swift && git commit -m "feat: persist voice message lab history"`.

### Task 3: Record, cancel, and play audio

**Files:**
- Create: `VoiceMessageLab/Audio/VoiceRecorder.swift`
- Create: `VoiceMessageLab/Audio/VoicePlayer.swift`
- Create: `VoiceMessageLabTests/VoiceRecorderStateTests.swift`

**Produces:** `VoiceRecorder.State.idle`, `.recording(elapsed:level:)`, `.failed(String)`; `func finish() async throws -> RecordedVoice`; and `func cancel() async`.

- [ ] Write the failing test:

```swift
func test_cancel_discardsFinalizedRecording() async throws {
    let recorder = VoiceRecorder(fileSystem: spyFileSystem)
    try await recorder.beginForTesting()
    await recorder.cancel()
    XCTAssertNil(recorder.lastCompletedRecording)
    XCTAssertFalse(spyFileSystem.removedURLs.isEmpty)
}
```

- [ ] Run `xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -only-testing:VoiceMessageLabTests/VoiceRecorderStateTests test -destination 'generic/platform=iOS Simulator'`; expect a missing-recorder failure.
- [ ] Implement `AVAudioRecorder` with `.playAndRecord`, `.spokenAudio`, `.defaultToSpeaker`, AAC output in Application Support, metering, and deletion on cancellation. Implement player to stop the previous file before play.
- [ ] Rerun test and `xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -destination 'generic/platform=iOS Simulator' build`; expect green/build success.
- [ ] Commit: `git add VoiceMessageLab/Audio VoiceMessageLabTests/VoiceRecorderStateTests.swift && git commit -m "feat: record and play local voice messages"`.

### Task 4: Create message immediately and transcribe independently

**Files:**
- Create: `VoiceMessageLab/Transcription/VoiceTranscriber.swift`
- Create: `VoiceMessageLab/Presentation/VoiceMessageLabModel.swift`
- Create: `VoiceMessageLabTests/VoiceMessageLabModelTests.swift`

**Produces:** `protocol VoiceTranscriber { func transcribe(url: URL) async throws -> String }` and `@Observable final class VoiceMessageLabModel` with `messages` and `finishRecording()`.

- [ ] Write the failing test:

```swift
func test_finishRecording_addsAudioBeforeTranscriptCompletes() async throws {
    let transcriber = ControlledTranscriber()
    let model = makeModel(transcriber: transcriber)
    await model.finishRecording()
    XCTAssertEqual(model.messages.first?.transcript, .pending)
    await transcriber.complete(with: "Привет")
    XCTAssertEqual(model.messages.first?.transcript, .ready("Привет"))
}
```

- [ ] Run `xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -only-testing:VoiceMessageLabTests/VoiceMessageLabModelTests test -destination 'generic/platform=iOS Simulator'`; expect a missing-model failure.
- [ ] Append and persist the `VoiceMessage` first, then launch a task that invokes `VoiceTranscriber`, updates the transcript on the main actor, and persists again. Production adapter loads Parakeet and transcribes the completed audio in Russian. A failure becomes `.failed` without altering audio.
- [ ] Rerun the test; expect green.
- [ ] Commit: `git add VoiceMessageLab/Transcription VoiceMessageLab/Presentation VoiceMessageLabTests/VoiceMessageLabModelTests.swift && git commit -m "feat: transcribe voice messages independently"`.

### Task 5: Build the chat prototype and ready it for the iPhone

**Files:**
- Create: `VoiceMessageLab/Presentation/VoiceMessageLabScreen.swift`
- Modify: `VoiceMessageLab/App/VoiceMessageLabApp.swift`

**Consumes:** `VoiceMessageLabModel`, `VoiceRecorder.State`, `VoicePlayer`.

- [ ] Write the failing state test:

```swift
func test_recordingState_exposesCancelAffordance() {
    XCTAssertEqual(VoiceComposerPresentation(state: .recording).action, .cancelBySliding)
}
```

- [ ] Run the Task 4 test command; expect a missing-presentation failure.
- [ ] Implement hold-then-drag recording with start haptic; visual duration/meter; left-drag cancellation; play/pause and duration in the audio bubble; pending transcript text and local `Показать ещё` disclosure.
- [ ] Rerun tests, then run:

```bash
xcodegen generate
xcodebuild -project TaskFlow.xcodeproj -scheme VoiceMessageLab -configuration Debug -destination 'generic/platform=iOS' build
```

Expected: all tests pass and device build is ready. Install only after the owner connects and unlocks the iPhone.
- [ ] Commit: `git add VoiceMessageLab VoiceMessageLabTests project.yml && git commit -m "feat: add voice message lab prototype"`.

## Final Verification

- [ ] `git diff --check` passes for scoped files.
- [ ] Full `VoiceMessageLab` test suite passes with a fresh derived-data path.
- [ ] Device build succeeds before requesting the iPhone.
- [ ] On iPhone: grant microphone permission, record/cancel, record/send, play on speaker and headphones, wait for transcript, restart app, verify restoration.

## Plan Self-Review

- Spec coverage: Tasks 1–5 cover isolation, AAC, persistence, cancellation, playback, independent transcript, visible states, and device acceptance.
- Placeholder scan: no deferred implementation markers; server integration is explicitly out of scope.
- Type consistency: later tasks consume interfaces introduced by prior tasks.
