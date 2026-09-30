import Foundation
import AVFoundation

enum VoiceWaveform {
    /// Огибающая из РЕАЛЬНОГО аудиофайла: читаем PCM, считаем RMS по корзинам,
    /// нормируем. Это «настоящая» волна по всему файлу, а не живые уровни,
    /// которые при короткой/тихой записи схлопываются в точки
    /// (владелец 21.09.2026).
    static func envelope(fromAudioFile url: URL, bars: Int = 48) -> [Double] {
        guard bars > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return [] }
        do { try file.read(into: buffer) } catch { return [] }
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let total = Int(buffer.frameLength)
        guard total > 0 else { return [] }

        let bucket = max(1, total / bars)
        var out: [Double] = []
        out.reserveCapacity(bars)
        var index = 0
        while index < total && out.count < bars {
            let end = min(index + bucket, total)
            var sum = 0.0
            for i in index..<end {
                let value = Double(channel[i])
                sum += value * value
            }
            out.append((sum / Double(end - index)).squareRoot())
            index = end
        }
        let peak = out.max() ?? 0
        guard peak > 0 else { return out }
        return out.map { min(1, $0 / peak) }
    }

    static func microphoneLevel(averageDecibels: Float, peakDecibels: Float) -> Double {
        let speechThreshold: Float = -38
        guard averageDecibels > speechThreshold else { return 0 }

        func normalize(_ decibels: Float) -> Double {
            let progress = max(0, min(1, (decibels - speechThreshold) / 42))
            return pow(Double(progress), 0.45)
        }

        return min(1, normalize(averageDecibels) * 0.65 + normalize(peakDecibels) * 0.35)
    }

    /// Уровень для живой волны записи: без ожидания нескольких отсчётов.
    /// Тихие слоги остаются видимыми, пауза плавно затухает примерно за 0,7 с.
    static func recordingLevel(previous: Double, averageDecibels: Float, peakDecibels: Float) -> Double {
        func normalize(_ decibels: Float) -> Double {
            guard decibels.isFinite else { return 0 }
            let progress = Double(max(0, min(1, (decibels + 60) / 60)))
            return pow(progress, 0.6)
        }
        let input = normalize(averageDecibels) * 0.65 + normalize(peakDecibels) * 0.35
        let response = input > previous ? 0.68 : 0.12
        return min(0.9, max(0, previous + (input - previous) * response))
    }

    static func displaySamples(from samples: [Double], slots: Int) -> [Double] {
        guard slots > 0 else { return [] }
        let visible = Array(samples.suffix(slots))
        return Array(repeating: 0, count: slots - visible.count) + visible
    }

    static func sculptedSamples(from samples: [Double]) -> [Double] {
        var previousRaw = 0.0
        var envelope = 0.0

        return samples.map { raw in
            let level = min(max(raw, 0), 1)
            let target: Double
            if level > previousRaw + 0.035 {
                target = level
            } else {
                target = level * 0.28
            }
            envelope += (target - envelope) * 0.72
            previousRaw = level
            return envelope
        }
    }

    static func smoothedLevel(previous: Double, raw: Double) -> Double {
        let input = min(max(raw, 0), 1)
        let response = input > previous ? 0.68 : 0.85
        return min(0.9, previous + (input - previous) * response)
    }
}
