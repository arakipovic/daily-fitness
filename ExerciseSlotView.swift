import SwiftUI

struct ExerciseSlotView: View {
    let slot: Slot
    let unit: Unit
    let videos: [String: URL]
    let exerciseIndex: [String: ExerciseLog]
    let previousLog: ExerciseLog?
    let recommendation: WorkoutRecommendation?
    @Binding var exerciseLog: ExerciseLog
    let onSetDone: (Int) -> Void

    @State private var showingNotes = false
    @State private var showingVideo = false
    @State private var showingReadinessInfo = false
    @State private var showingRecInfo = false

    private var videoURL: URL? {
        videos[exerciseLog.exerciseName] ?? videos[slot.name]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exerciseHeader

            if let rec = recommendation {
                recommendationBadge(rec)
            }

            if let prev = previousLog {
                prevSummaryRow(prev)
            }

            if showingNotes || !exerciseLog.note.isEmpty {
                TextField("Note…", text: $exerciseLog.note, axis: .vertical)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider().padding(.horizontal, 16)

            ForEach(exerciseLog.sets.indices, id: \.self) { i in
                SetRowView(
                    setNumber: i + 1,
                    entry: entryBinding(i),
                    previousEntry: previousLog?.sets[safe: i],
                    unit: unit,
                    onDone: { onSetDone(slot.restSeconds) }
                )
                if i < exerciseLog.sets.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }

            addSetButton
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingVideo) {
            if let url = videoURL {
                VideoPlayerSheet(url: url, exerciseName: exerciseLog.exerciseName)
            }
        }
    }

    // MARK: - Header

    private var exerciseHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(slot.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    if exerciseLog.swappedFrom != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text(exerciseLog.exerciseName)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("\(slot.sets) × \(slot.reps)")
                    Text("·")
                    Text(restLabel(slot.restSeconds) + " rest")
                    Text("·")
                    Text("RIR \(slot.rir)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !slot.notes.isEmpty {
                    Text(slot.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Spacer()

            HStack(spacing: 6) {
                // Prominent play button when video is available
                if videoURL != nil {
                    Button {
                        showingVideo = true
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Menu {
                    if !slot.alternatives.isEmpty {
                        Menu("Swap Exercise") {
                            // Primary exercise (revert to original)
                            Button {
                                exerciseLog.exerciseName = slot.name
                                exerciseLog.swappedFrom = nil
                            } label: {
                                if exerciseIndex[slot.name.lowercased()] != nil {
                                    Label(slot.name, systemImage: "clock")
                                } else {
                                    Text(slot.name)
                                }
                            }
                            Divider()
                            // Alternatives with history first, then without
                            let altsWithHistory = slot.alternatives.filter { exerciseIndex[$0.lowercased()] != nil }
                            let altsNoHistory = slot.alternatives.filter { exerciseIndex[$0.lowercased()] == nil }
                            ForEach(altsWithHistory, id: \.self) { alt in
                                Button {
                                    if exerciseLog.swappedFrom == nil {
                                        exerciseLog.swappedFrom = exerciseLog.exerciseName
                                    }
                                    exerciseLog.exerciseName = alt
                                } label: {
                                    Label(alt, systemImage: "clock")
                                }
                            }
                            if !altsWithHistory.isEmpty && !altsNoHistory.isEmpty {
                                Divider()
                            }
                            ForEach(altsNoHistory, id: \.self) { alt in
                                Button(alt) {
                                    if exerciseLog.swappedFrom == nil {
                                        exerciseLog.swappedFrom = exerciseLog.exerciseName
                                    }
                                    exerciseLog.exerciseName = alt
                                }
                            }
                        }
                    }
                    Button {
                        withAnimation { showingNotes.toggle() }
                    } label: {
                        Label(exerciseLog.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Recommendation badge

    private func recommendationBadge(_ rec: WorkoutRecommendation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: rec.systemImage)
                .foregroundStyle(rec.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rec.directionLabel)
                        .fontWeight(.semibold)
                    Button {
                        showingRecInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingRecInfo) {
                        RecommendationInfoView()
                    }
                    Text("·")
                    Text(rec.suggestedWeight > 0
                         ? "\(rec.weightString) \(unit.rawValue) × \(rec.suggestedReps)"
                         : "\(rec.suggestedReps) reps")
                }
                .font(.subheadline)
                Text(rec.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Capsule()
                    .fill(rec.readinessColor.opacity(0.18))
                    .frame(width: 58, height: 22)
                    .overlay(
                        Text(rec.readinessLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(rec.readinessColor)
                    )
                Button {
                    showingReadinessInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingReadinessInfo) {
                    ReadinessInfoView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(rec.color.opacity(0.06))
    }

    // MARK: - Previous performance row

    private func prevSummaryRow(_ prev: ExerciseLog) -> some View {
        let parts = prev.sets
            .filter { !$0.weight.isEmpty && !$0.reps.isEmpty && $0.done }
            .map { "\($0.weight)×\($0.reps)" }
        let text = parts.isEmpty ? "No previous data" : parts.joined(separator: "  ")
        return HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Add Set

    private var addSetButton: some View {
        Button {
            let last = exerciseLog.sets.last
            exerciseLog.sets.append(SetEntry(id: UUID(), weight: last?.weight ?? "", reps: last?.reps ?? "", rir: "2", done: false))
        } label: {
            Label("Add Set", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func entryBinding(_ i: Int) -> Binding<SetEntry> {
        Binding {
            exerciseLog.sets.indices.contains(i)
                ? exerciseLog.sets[i]
                : SetEntry(id: UUID(), weight: "", reps: "", rir: "2", done: false)
        } set: { val in
            if exerciseLog.sets.indices.contains(i) {
                exerciseLog.sets[i] = val
            }
        }
    }

    private func restLabel(_ seconds: Int) -> String {
        seconds >= 60
            ? "\(seconds / 60)m\(seconds % 60 == 0 ? "" : "\(seconds % 60)s")"
            : "\(seconds)s"
    }
}

// MARK: - Readiness Info Popover

private struct ReadinessInfoView: View {
    private struct Tier {
        let label: String
        let color: Color
        let description: String
    }
    private let tiers: [Tier] = [
        Tier(label: "High",     color: .green,  description: "Well-rested and recovered — push harder today."),
        Tier(label: "Moderate", color: .yellow, description: "Good conditions — stay at your current load."),
        Tier(label: "Low",      color: .orange, description: "Signs of fatigue — take it a little easier."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Readiness Score")
                .font(.headline)
            ForEach(tiers, id: \.label) { tier in
                HStack(alignment: .top, spacing: 10) {
                    Capsule()
                        .fill(tier.color.opacity(0.18))
                        .frame(width: 66, height: 22)
                        .overlay(
                            Text(tier.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tier.color)
                        )
                    Text(tier.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Based on last night's sleep and days since your last session.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Recommendation Info Popover

struct RecommendationInfoView: View {
    private struct DirectionInfo {
        let icon: String
        let color: Color
        let label: String
        let description: String
    }
    private let directions: [DirectionInfo] = [
        DirectionInfo(icon: "arrow.up.circle.fill",   color: .green,    label: "Progress",
                      description: "You hit the top of your rep range — add weight next set."),
        DirectionInfo(icon: "equal.circle.fill",       color: .accentColor, label: "Maintain",
                      description: "Stay at the same weight and try for one more rep."),
        DirectionInfo(icon: "arrow.down.circle.fill",  color: .orange,   label: "Recover",
                      description: "Signs of fatigue — reduce weight by ~10% today."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading the Suggestion")
                .font(.headline)

            ForEach(directions, id: \.label) { d in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: d.icon)
                        .foregroundStyle(d.color)
                        .frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.label)
                            .font(.subheadline.weight(.semibold))
                        Text(d.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("100 kg × 9")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("= suggested weight × target reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Based on your last performance, sleep quality, and days since your last session.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Set Row

private struct SetRowView: View {
    let setNumber: Int
    @Binding var entry: SetEntry
    let previousEntry: SetEntry?
    let unit: Unit
    let onDone: () -> Void

    private var weightPlaceholder: String {
        previousEntry.flatMap { $0.weight.isEmpty ? nil : $0.weight } ?? "0"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(setNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.done ? .tertiary : .secondary)
                .frame(width: 24, alignment: .center)
                .padding(.leading, 16)

            // Weight field
            VStack(spacing: 1) {
                TextField(weightPlaceholder, text: $entry.weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.medium))
                    .disabled(entry.done)
                Text(unit.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(entry.done ? Color.clear : Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Reps stepper
            RepsStepperView(reps: $entry.reps, disabled: entry.done,
                            previousReps: previousEntry.flatMap { $0.reps.isEmpty ? nil : $0.reps })

            // RIR picker
            Picker("RIR", selection: $entry.rir) {
                ForEach(["F", "0", "1", "2", "3", "4", "5"], id: \.self) { r in
                    Text(r).tag(r)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 52)
            .disabled(entry.done)

            // Done button
            Button {
                withAnimation(.spring(duration: 0.2)) { entry.done.toggle() }
                if entry.done { onDone() }
            } label: {
                Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.done ? Color.green : Color(.tertiaryLabel))
            }
            .frame(width: 44)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .background(entry.done ? Color.green.opacity(0.07) : Color.clear)
    }
}

// MARK: - Reps Stepper

private struct RepsStepperView: View {
    @Binding var reps: String
    let disabled: Bool
    let previousReps: String?

    private var current: Int? { Int(reps) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                let n = (current ?? 1) - 1
                if n >= 1 { reps = "\(n)" }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(disabled || (current ?? 0) <= 1)

            TextField(previousReps ?? "0", text: $reps)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline.weight(.medium))
                .frame(width: 32)
                .disabled(disabled)

            Button {
                reps = "\((current ?? 0) + 1)"
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(disabled)
        }
        .background(disabled ? Color.clear : Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
