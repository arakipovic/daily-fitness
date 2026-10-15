import Foundation
import SwiftUI

// MARK: - Recommendation output

struct WorkoutRecommendation {
    let suggestedWeight: Double   // in the user's unit; 0 means unable to suggest
    let suggestedReps: Int
    let direction: Direction
    let readiness: Double         // 0.0 – 1.0
    let reason: String            // e.g. "8.2h sleep · 2 days rest"

    enum Direction: Equatable {
        case progress   // ↑ go heavier
        case maintain   // → same weight
        case deload     // ↓ back off today
    }

    var systemImage: String {
        switch direction {
        case .progress: return "arrow.up.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .deload:   return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch direction {
        case .progress: return .green
        case .maintain: return .accentColor
        case .deload:   return .orange
        }
    }

    var directionLabel: String {
        switch direction {
        case .progress: return "Progress"
        case .maintain: return "Maintain"
        case .deload:   return "Recover"
        }
    }

    var readinessLabel: String { WorkoutRecommendation.label(for: readiness) }
    var readinessColor: Color  { WorkoutRecommendation.color(for: readiness) }

    /// Label and color helpers usable anywhere a raw readiness score is available
    /// (e.g. DayCard) without needing a full WorkoutRecommendation object.
    static func label(for score: Double) -> String {
        switch score {
        case 0.85...: return "High"
        case 0.65..<0.85: return "Moderate"
        default: return "Low"
        }
    }

    static func color(for score: Double) -> Color {
        switch score {
        case 0.85...: return .green
        case 0.65..<0.85: return .yellow
        default: return .orange
        }
    }

    /// Pre-fill string for the weight field ("82.5", "80", etc.)
    var weightString: String {
        suggestedWeight == 0 ? "" : formatWeight(suggestedWeight)
    }

    private func formatWeight(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

// MARK: - Recommender

enum WorkoutRecommender {

    // MARK: Per-exercise recommendation

    static func recommend(
        previousLog: ExerciseLog?,
        slot: Slot,
        unit: Unit,
        sleepHours: Double?,
        daysSinceLastSession: Int?
    ) -> WorkoutRecommendation? {
        guard let prev = previousLog else { return nil }

        // Best done set = highest weight with reps logged
        let doneSets = prev.sets.filter { $0.done && !$0.weight.isEmpty }
        guard let bestSet = doneSets.max(by: { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }) else { return nil }

        let prevWeight = Double(bestSet.weight) ?? 0
        guard prevWeight > 0 else { return nil }

        let prevReps      = Int(bestSet.reps) ?? 0
        let (repMin, repMax) = parseRepRange(slot.reps)
        let readiness     = sessionReadiness(sleepHours: sleepHours, daysSinceLastSession: daysSinceLastSession)
        let step          = unit == .kg ? 2.5 : 5.0

        let direction: WorkoutRecommendation.Direction
        let suggestedWeight: Double
        let suggestedReps: Int

        if readiness >= 0.85 && prevReps >= repMax {
            // Slept well, recovered, hit top of rep range → add weight
            direction       = .progress
            suggestedWeight = roundToStep(prevWeight + step, step: step)
            suggestedReps   = repMin
        } else if readiness >= 0.65 {
            // Good-to-moderate readiness → maintain, aim for one more rep
            direction       = .maintain
            suggestedWeight = prevWeight
            suggestedReps   = min(prevReps + 1, repMax)
        } else {
            // Low readiness → slight deload
            direction       = .deload
            suggestedWeight = roundToStep(prevWeight * 0.90, step: step)
            suggestedReps   = (repMin + repMax) / 2
        }

        return WorkoutRecommendation(
            suggestedWeight: suggestedWeight,
            suggestedReps:   suggestedReps,
            direction:       direction,
            readiness:       readiness,
            reason:          buildReason(direction: direction, sleepHours: sleepHours, days: daysSinceLastSession)
        )
    }

    // MARK: Session-level readiness (for DayCard preview)

    static func sessionReadiness(sleepHours: Double?, daysSinceLastSession: Int?) -> Double {
        0.40 * sleepFactor(sleepHours) + 0.60 * recoveryFactor(daysSinceLastSession)
    }

    // MARK: Rep-range parsing

    static func parseRepRange(_ reps: String) -> (min: Int, max: Int) {
        let parts = reps.components(separatedBy: "-")
        if parts.count == 2,
           let lo = Int(parts[0].trimmingCharacters(in: .whitespaces)),
           let hi = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
            return (lo, hi)
        }
        if let single = Int(reps.trimmingCharacters(in: .whitespaces)) {
            return (single, single)
        }
        return (8, 12)
    }

    // MARK: - Private

    private static func sleepFactor(_ hours: Double?) -> Double {
        guard let h = hours else { return 0.85 }
        switch h {
        case 8...:  return 1.00
        case 7..<8: return 0.90
        case 6..<7: return 0.75
        case 5..<6: return 0.60
        default:    return 0.45
        }
    }

    private static func recoveryFactor(_ days: Int?) -> Double {
        guard let d = days else { return 0.90 }
        switch d {
        case 2...: return 1.00
        case 1:    return 0.85
        case 0:    return 0.65
        default:   return 1.00
        }
    }

    private static func roundToStep(_ value: Double, step: Double) -> Double {
        (value / step).rounded() * step
    }

    private static func buildReason(
        direction: WorkoutRecommendation.Direction,
        sleepHours: Double?,
        days: Int?
    ) -> String {
        var parts: [String] = []
        if let h = sleepHours { parts.append(String(format: "%.1fh sleep", h)) }
        if let d = days { parts.append(d == 1 ? "1 day rest" : "\(d) days rest") }
        let context = parts.isEmpty ? "no health data" : parts.joined(separator: " · ")
        switch direction {
        case .progress: return "Push — \(context)"
        case .maintain: return parts.isEmpty ? "Stay the course" : context
        case .deload:   return "Take it easy — \(context)"
        }
    }
}
