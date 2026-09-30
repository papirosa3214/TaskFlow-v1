import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(url: URL) throws {
        if playingURL == url {
            stop()
            return
        }
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        self.player = player
        player.delegate = self
        player.play()
        playingURL = url
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stop() }
    }
}
