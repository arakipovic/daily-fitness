import Foundation
import SwiftUI

// MARK: - Event store

final class Analytics {
    static let shared = Analytics()
    private init() {}

    struct Event: Codable {
        let name: String
        let properties: [String: String]
        let timestamp: Date
    }

    private let maxEvents = 5_000
    private let queue = DispatchQueue(label: "app.dailyfitness.analytics", qos: .utility)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("analytics.jsonl")
    }

    func track(_ name: String, _ properties: [String: String] = [:]) {
        let event = Event(name: name, properties: properties, timestamp: Date())
        queue.async { [self] in
            guard let data = try? self.encoder.encode(event),
                  let line = String(data: data, encoding: .utf8) else { return }
            self.append(line)
        }
    }

    func screen(_ name: String) {
        track("screen_viewed", ["screen": name])
    }

    private func append(_ line: String) {
        let url = fileURL
        let newLine = line + "\n"
        let fm = FileManager.default

        if fm.fileExists(atPath: url.path) {
            guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
                try? Data(newLine.utf8).write(to: url)
                return
            }
            var lines = existing.components(separatedBy: "\n").filter { !$0.isEmpty }
            if lines.count >= maxEvents {
                lines = Array(lines.suffix(maxEvents - 1))
                try? (lines.joined(separator: "\n") + "\n" + line + "\n")
                    .write(to: url, atomically: true, encoding: .utf8)
            } else if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(newLine.utf8))
                try? handle.close()
            }
        } else {
            try? Data(newLine.utf8).write(to: url)
        }
    }

    func allEvents() -> [Event] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? decoder.decode(Event.self, from: Data($0.utf8)) }
    }
}

// MARK: - SwiftUI convenience

extension View {
    func trackScreen(_ name: String) -> some View {
        onAppear { Analytics.shared.screen(name) }
    }
}
