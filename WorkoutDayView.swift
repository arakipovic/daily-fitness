import SwiftUI

struct WorkoutDayView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    let programID: String
    let week: Int
    let day: ProgramDay

    @Environment(\.dismiss) private var dismiss

    @State private var session: SessionLog
    @State private var elapsedSeconds: Int = 0
    @State private var restRemaining: Int = 0
    @State private var restTotal: Int = 90
    @State private var showingDeleteConfirm = false
    @State private var showingTimeEditor = false
    @State private var isDeleted = false
    @State private var workoutTimerTask: Task<Void, Never>? = nil
    @State private var restTimerTask: Task<Void, Never>? = nil

    init(programID: String, week: Int, day: ProgramDay, existingSession: SessionLog? = nil) {
        self.programID = programID
        self.week = week
        self.day = day
        _session = State(initialValue: existingSession ?? SessionLog(
            programID: programID, week: week, day: day.number,
            started: nil, completed: nil, slotLogs: [:]
        ))
    }

    var isCompleted: Bool { session.completed != nil }
    var completedSets: Int {
        session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }
    var totalSets: Int { day.exercises.reduce(0) { $0 + $1.sets } }

    private var dayTitle: String {
        store.catalog.programs.first { $0.id == programID }
            .map { $0.dayFocusTitle(for: day) } ?? "Day \(day.number)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if restRemaining > 0 {
                RestTimerBannerView(remaining: $restRemaining, total: restTotal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            progressHeader

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(day.exercises) { slot in
                        ExerciseSlotView(
                            slot: slot,
                            unit: store.logbook.unit,
                            videos: store.catalog.videos,
                            exerciseIndex: store.exerciseIndex,
                            previousLog: bestPreviousLog(for: slot),
                            recommendation: recommendation(for: slot),
                            exerciseLog: bindingForSlot(slot),
                            onSetDone: { seconds in
                                startRestTimer(seconds: seconds)
                                store.updateSessionImmediately(session)
                            }
                        )
                    }

                    completeSection
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Week \(week) · \(dayTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingTimeEditor = true } label: {
                    HStack(spacing: 3) {
                        Text(timeString(elapsedSeconds))
                            .font(.system(.callout, design: .monospaced))
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                isDeleted = true
                workoutTimerTask?.cancel()
                restTimerTask?.cancel()
                store.deleteSession(programID: programID, week: week, day: day.number)
                dismiss()
            }
        } message: {
            Text("All logged sets for this session will be permanently removed.")
        }
        .sheet(isPresented: $showingTimeEditor) {
            TimeEditorSheet(session: $session) {
                if let started = session.started {
                    elapsedSeconds = Int(Date().timeIntervalSince(started))
                }
            }
        }
        .onAppear {
            Analytics.shared.screen("workout_day")
            if session.started == nil && !isCompleted {
                session.started = Date()
                prefillFromPreviousSession()
                saveSession()
            }
            startWorkoutTimer()
        }
        .onChange(of: store.exerciseIndex.count) { _, newCount in
            // exerciseIndex is built asynchronously — re-prefill once it's populated
            // so slots that were empty due to timing get weights filled in
            guard newCount > 0, !isCompleted else { return }
            let hadEmptySlot = day.exercises.contains { slot in
                let log = session.slotLogs[slot.label]
                return log == nil || log!.sets.allSatisfy { $0.weight.isEmpty }
            }
            if hadEmptySlot {
                prefillFromPreviousSession()
                saveSession()
            }
        }
        .onDisappear {
            workoutTimerTask?.cancel()
            restTimerTask?.cancel()
            if !isDeleted {
                // Write immediately — the debounce window may not finish if the
                // user backgrounds the app right after navigating away.
                store.updateSession(session)
                store.saveImmediately()
            }
        }
        .animation(.spring(duration: 0.35), value: restRemaining > 0)
    }

    // MARK: - Subviews

    private var progressHeader: some View {
        HStack(spacing: 16) {
            ProgressView(value: Double(completedSets), total: Double(max(1, totalSets)))
                .tint(isCompleted ? .green : .accentColor)
                .frame(maxWidth: .infinity)
            Text("\(completedSets)/\(totalSets)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCompleted ? .green : .primary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var completeSection: some View {
        if !isCompleted {
            Button {
                withAnimation {
                    session.completed = Date()
                    restTimerTask?.cancel()
                    restRemaining = 0
                }
                workoutTimerTask?.cancel()
                saveSession()
            } label: {
                Label("Complete Workout", systemImage: "flag.checkered")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(completedSets == 0)
            .padding(.top, 8)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("Workout Complete!")
                    .font(.title3.weight(.semibold))
                if let completed = session.completed {
                    Text("Finished at \(completed.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let kcal = estimatedKcal {
                    Text("~\(kcal) kcal burned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Helpers

    private func bindingForSlot(_ slot: Slot) -> Binding<ExerciseLog> {
        Binding {
            session.slotLogs[slot.label] ?? ExerciseLog(
                exerciseName: WorkoutLogic.preferredExercise(for: slot, exerciseIndex: store.exerciseIndex),
                sets: (0..<slot.sets).map { _ in
                    SetEntry(id: UUID(), weight: "", reps: "", rir: "2", done: false)
                },
                note: "",
                swappedFrom: nil
            )
        } set: { newLog in
            session.slotLogs[slot.label] = newLog
        }
    }

    private func recommendation(for slot: Slot) -> WorkoutRecommendation? {
        let prev = bestPreviousLog(for: slot)
        return WorkoutRecommender.recommend(
            previousLog: prev,
            slot: slot,
            unit: store.logbook.unit,
            sleepHours: healthKit.lastNightSleep?.asleepHours,
            daysSinceLastSession: store.daysSinceLastSession()
        )
    }

    private func prefillFromPreviousSession() {
        for slot in day.exercises {
            // Skip only if the user has already touched this slot (done or entered weight)
            let existing = session.slotLogs[slot.label]
            let userHasInput = existing?.sets.contains { $0.done || !$0.weight.isEmpty } == true
            if userHasInput { continue }

            guard let prev = bestPreviousLog(for: slot) else { continue }

            // Best done weight from previous session, falling back to any entered weight
            let bestPrevWeight = prev.sets
                .filter { $0.done && !$0.weight.isEmpty }
                .max { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }?.weight
                ?? prev.sets.first(where: { !$0.weight.isEmpty })?.weight
                ?? ""

            let rec = recommendation(for: slot)
            // Only use rec values when the recommender produced real data (> 0)
            let fillWeight = rec.flatMap { $0.suggestedWeight > 0 ? $0.weightString : nil }
                ?? bestPrevWeight
            let fillReps = rec.flatMap { $0.suggestedReps > 0 ? "\($0.suggestedReps)" : nil }
                ?? prev.sets.filter { $0.done && !$0.reps.isEmpty }.first?.reps
                ?? ""

            session.slotLogs[slot.label] = ExerciseLog(
                exerciseName: prev.exerciseName,
                sets: (0..<slot.sets).map { _ in
                    SetEntry(id: UUID(), weight: fillWeight, reps: fillReps, rir: "2", done: false)
                },
                note: "",
                swappedFrom: prev.exerciseName != slot.name ? slot.name : nil
            )
        }
    }

    private var estimatedKcal: Int? {
        WorkoutLogic.estimatedKcalBurned(
            session: session,
            weightKg: healthKit.recentWeightKg ?? store.resolvedBodyWeightKg
        )
    }

    /// Returns the most relevant previous ExerciseLog for the slot:
    /// prefers exact same-program/week history, then checks primary and all alternatives.
    private func bestPreviousLog(for slot: Slot) -> ExerciseLog? {
        if let prev = store.previousPerformance(
            programID: programID, currentWeek: week,
            dayNumber: day.number, slotLabel: slot.label
        ) { return prev }
        let candidates = [slot.name] + slot.alternatives
        return candidates.compactMap { store.lastKnownPerformance(exerciseName: $0) }.first
    }

    private func saveSession() {
        store.updateSession(session)
    }

    private func startWorkoutTimer() {
        workoutTimerTask?.cancel()
        if let started = session.started {
            elapsedSeconds = Int(Date().timeIntervalSince(started))
        }
        workoutTimerTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    elapsedSeconds += 1
                } catch {
                    break
                }
            }
        }
    }

    private func startRestTimer(seconds: Int) {
        restTimerTask?.cancel()
        restTotal = seconds
        restRemaining = seconds
        restTimerTask = Task {
            while !Task.isCancelled && restRemaining > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    restRemaining = max(0, restRemaining - 1)
                } catch {
                    break
                }
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Session Time Editor

private struct TimeEditorSheet: View {
    @Binding var session: SessionLog
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Start Time") {
                    DatePicker(
                        "Start",
                        selection: Binding(
                            get: { session.started ?? Date() },
                            set: { session.started = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if session.completed != nil {
                    Section("End Time") {
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { session.completed ?? Date() },
                                set: { session.completed = $0 }
                            ),
                            in: (session.started ?? .distantPast)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let start = session.started, let end = session.completed {
                    let secs = max(0, Int(end.timeIntervalSince(start)))
                    let h = secs / 3600
                    let m = (secs % 3600) / 60
                    Section {
                        LabeledContent("Duration") {
                            Text(h > 0 ? "\(h)h \(m)m" : "\(m) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Session Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rest Timer Banner

struct RestTimerBannerView: View {
    @Binding var remaining: Int
    let total: Int

    private var progress: Double {
        remaining <= 0 ? 1.0 : 1.0 - Double(remaining) / Double(max(1, total))
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        remaining <= 10 ? Color.orange : Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text("Rest")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timeString(remaining))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(remaining <= 10 ? .orange : .primary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { remaining = max(0, remaining - 15) } label: {
                    Text("−15s").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { remaining += 15 } label: {
                    Text("+15s").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { remaining = 0 } label: {
                    Text("Skip").font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle()
                    .fill(remaining <= 10 ? Color.orange : Color.accentColor)
                    .frame(width: geo.size.width * (1.0 - progress))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(height: 2)
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
