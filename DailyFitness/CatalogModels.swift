// CatalogModels.swift
// Models for the training program catalog and exercises

import Foundation

struct Catalog: Codable {
    var programs: [TrainingProgram]
    var videos: [String: URL]
}

struct TrainingProgram: Codable, Identifiable {
    var id: String
    var name: String
    var daysPerWeek: Int
    var title: String
    var weeks: Int
    var days: [ProgramDay]
}

struct ProgramDay: Codable, Identifiable {
    var id: Int { number }
    var number: Int
    var exercises: [Slot]
}

struct Slot: Codable, Identifiable {
    var id: String { label }
    var label: String
    var name: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var rir: String
    var notes: String
    var alternatives: [String]
}

// MARK: - TrainingProgram helpers

extension TrainingProgram {
    /// Human-readable day focus label ("Upper A", "Lower B", etc.).
    func dayFocusTitle(for day: ProgramDay) -> String {
        let titles: [String]
        switch daysPerWeek {
        case 4: titles = ["Upper A", "Lower A", "Upper B", "Lower B"]
        case 5: titles = ["Upper A", "Lower A", "Upper B", "Lower B", "Full Body"]
        default: return "Day \(day.number)"
        }
        let idx = day.number - 1
        return titles.indices.contains(idx) ? titles[idx] : "Day \(day.number)"
    }
}

// MARK: - Safe array subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
