// LiveActivityDiag.swift
// Куда писать диагностику островка, чтобы её было видно.
//
// ⚠️ NSLog НЕ ГОДИТСЯ: он уходит в системный журнал, а `xcrun devicectl
// device process launch --console` показывает только прямой вывод процесса.
// 10.09.2026 из-за этого лог с телефона пришёл пустым, и разбирательство
// встало на ровном месте.
//
// Поэтому пишем в оба места сразу: print — для живой консоли, файл — чтобы
// забрать постфактум (`devicectl device copy from --domain-type
// appDataContainer`), когда телефон уже отключили.

import Foundation

enum Diag {
    private static let fileURL: URL? = {
        try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("live-activity.log")
    }()

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)"
        print(line)
        guard let fileURL, let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
