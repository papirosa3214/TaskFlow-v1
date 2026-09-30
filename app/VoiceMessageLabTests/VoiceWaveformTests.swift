import XCTest
@testable import VoiceMessageLab

final class VoiceWaveformTests: XCTestCase {
    func test_displaySamplesKeepsFixedNumberOfSlotsWhileRecordingBegins() {
        let samples = VoiceWaveform.displaySamples(from: [0.72], slots: 8)

        XCTAssertEqual(samples.count, 8)
        XCTAssertEqual(samples.dropLast(), Array(repeating: 0, count: 7))
        XCTAssertEqual(samples.last, 0.72)
    }

    func test_smoothedLevelRespondsToSpeechWithinOneSample() {
        let smoothed = VoiceWaveform.smoothedLevel(previous: 0, raw: 1)

        XCTAssertGreaterThan(smoothed, 0.6)
        XCTAssertLessThan(smoothed, 0.8)
    }

    func test_microphoneDecibelsMapSpeechToVisibleAmplitude() {
        XCTAssertEqual(VoiceWaveform.microphoneLevel(averageDecibels: -60, peakDecibels: -60), 0)
        XCTAssertEqual(VoiceWaveform.microphoneLevel(averageDecibels: -48, peakDecibels: -10), 0)
        XCTAssertGreaterThan(
            VoiceWaveform.microphoneLevel(averageDecibels: -35, peakDecibels: -25),
            0.4
        )
    }

    func test_loudSpeechKeepsHeadroomBelowCeiling() {
        XCTAssertLessThan(
            VoiceWaveform.microphoneLevel(averageDecibels: -10, peakDecibels: -2),
            0.9
        )
    }

    func test_smoothedLevelDropsToBaselineWithinOneSilentSample() {
        XCTAssertLessThan(VoiceWaveform.smoothedLevel(previous: 0.8, raw: 0), 0.15)
    }

    func test_sculptedSamplesTurnFlatSpeechIntoAContour() {
        let contour = VoiceWaveform.sculptedSamples(from: [0, 0.7, 0.7, 0.7, 0.7])

        XCTAssertLessThan(contour[1], 0.6)
        XCTAssertGreaterThan(contour[1], contour[2])
        XCTAssertGreaterThan(contour[2], contour[3])
        XCTAssertLessThan(contour[2], 0.35)
    }
}
