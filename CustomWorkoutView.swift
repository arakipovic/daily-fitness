import SwiftUI

// MARK: - Custom Workout

struct CustomWorkoutView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.dismiss) private var dismiss

    let sessionWeek: Int

    @State private var session: SessionLog
    @State private var exerciseOrder: [String] = []
    @State private var elapsedSeconds: Int = 0
    @State private var showingExercisePicker = false
    @State private var showingCompleted = false
    @State private var showingCancelConfirm = false
    @State private var isCancelled = false
    @State private var workoutTimerTask: Task<Void, Never>? = nil

    // Rest timer
    @State private var restRemaining: Int = 0
    @State private var restTotal: Int = 90
    @State private var restTimerTask: Task<Void, Never>? = nil

    let isDuplicate: Bool
    let templateTitle: String
    let onDone: (() -> Void)?
    @State private var workoutDate: Date
    @State private var durationMinutes: Int

    init(sessionWeek: Int, template: SessionLog? = nil, onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        self.sessionWeek = sessionWeek
        self.isDuplicate = template != nil

        if let template {
            templateTitle = WorkoutLogic.sessionDisplayTitle(template)

            // Duplicate starts fresh today — the user is doing the same workout again, not logging the past
            _workoutDate = State(initialValue: Date())
            _durationMinutes = State(initialValue: 60)

            let (duplicated, order) = WorkoutLogic.duplicateSession(template: template, newWeek: sessionWeek)
            _session = State(initialValue: duplicated)
            _exerciseOrder = State(initialValue: order)
        } else {
            templateTitle = "Custom Workout"
            _workoutDate = State(initialValue: Date())
            _durationMinutes = State(initialValue: 60)
            _session = State(initialValue: SessionLog(
                programID: "custom", week: sessionWeek, day: 1,
                started: Date(), completed: nil, slotLogs: [:]
            ))
            _exerciseOrder = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingCompleted {
                    completedView
                } else {
                    exerciseListView
                }
            }
            .navigationTitle(isDuplicate ? templateTitle : "Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        let hasData = !exerciseOrder.isEmpty && session.slotLogs.values.contains {
                            $0.sets.contains { $0.done || !$0.weight.isEmpty }
                        }
                        if hasData && !isDuplicate {
                            showingCancelConfirm = true
                        } else {
                            cancelWorkout()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(timeString(elapsedSeconds))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog("Discard workout?", isPresented: $showingCancelConfirm, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { cancelWorkout() }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerSheet { name in addExercise(name: name) }
            }
        }
        .onAppear {
            store.updateSession(session)
            startTimer()
            // Auto-open picker for empty workouts so user isn't stuck on blank screen
            if exerciseOrder.isEmpty {
                showingExercisePicker = true
            }
        }
        .onDisappear {
            workoutTimerTask?.cancel()
            restTimerTask?.cancel()
            if !isCancelled && !showingCompleted {
                store.updateSessionImmediately(session)
            }
        }
    }

    // MARK: - Exercise List

    private var exerciseListView: some View {
        VStack(spacing: 0) {
            if restRemaining > 0 {
                RestTimerBannerView(remaining: $restRemaining, total: restTotal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(exerciseOrder, id: \.self) { label in
                        if session.slotLogs[label] != nil {
                            CustomExerciseCard(
                                exerciseName: session.slotLogs[label]!.exerciseName,
                                log: Binding(
                                    get: { session.slotLogs[label]! },
                                    set: { session.slotLogs[label] = $0 }
                                ),
                                previousLog: store.lastKnownPerformance(
                                    exerciseName: session.slotLogs[label]!.exerciseName
                                ),
                                unit: store.logbook.unit,
                                sleepHours: healthKit.lastNightSleep?.asleepHours,
                                daysSinceLastSession: store.daysSinceLastSession(),
                                onRemove: { removeExercise(label: label) },
                                onSetDone: { startRestTimer(seconds: 90) }
                            )
                        }
                    }

                    Button { showingExercisePicker = true } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if !exerciseOrder.isEmpty {
                        Button { completeWorkout() } label: {
                            Label("Complete Workout", systemImage: "flag.checkered")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .animation(.spring(duration: 0.35), value: restRemaining > 0)
    }

    // MARK: - Completed View

    private var completedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Workout Complete!")
                .font(.title2.weight(.bold))
            let setsLogged = session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
            Text("\(exerciseOrder.count) exercises · \(setsLogged) sets · \(timeString(elapsedSeconds))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            // Single dismiss: onDone closes the whole fullScreenCover chain
            Button("Done") { onDone?() ?? dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func addExercise(name: String) {
        store.addCustomExerciseName(name)
        let label = WorkoutLogic.nextSlotLabel(existingLabels: Set(session.slotLogs.keys))
        let prev = store.lastKnownPerformance(exerciseName: name)
        let bestSet = prev?.sets
            .filter { $0.done && !$0.weight.isEmpty }
            .max { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }
            ?? prev?.sets.first(where: { !$0.weight.isEmpty })
        let fillWeight = bestSet?.weight ?? ""
        let fillReps = bestSet?.reps ?? "10"   // default 10 reps when no history
        let defaultSets = 4
        session.slotLogs[label] = ExerciseLog(
            exerciseName: name,
            sets: (0..<defaultSets).map { _ in
                SetEntry(id: UUID(), weight: fillWeight, reps: fillReps, rir: "2", done: false)
            },
            note: "",
            swappedFrom: nil
        )
        exerciseOrder.append(label)
        store.updateSessionImmediately(session)
    }

    private func removeExercise(label: String) {
        session.slotLogs.removeValue(forKey: label)
        exerciseOrder.removeAll { $0 == label }
        store.updateSessionImmediately(session)
    }

    private func completeWorkout() {
        session.completed = Date()
        workoutTimerTask?.cancel()
        restTimerTask?.cancel()
        restRemaining = 0
        store.updateSessionImmediately(session)
        withAnimation { showingCompleted = true }
    }

    private func cancelWorkout() {
        isCancelled = true
        workoutTimerTask?.cancel()
        restTimerTask?.cancel()
        store.deleteSession(programID: "custom", week: sessionWeek, day: 1)
        dismiss()
    }

    private func startTimer() {
        workoutTimerTask?.cancel()
        if let started = session.started {
            elapsedSeconds = Int(Date().timeIntervalSince(started))
        }
        workoutTimerTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    elapsedSeconds += 1
                } catch { break }
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
                } catch { break }
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Custom Exercise Card

private struct CustomExerciseCard: View {
    let exerciseName: String
    @Binding var log: ExerciseLog
    let previousLog: ExerciseLog?
    let unit: Unit
    let sleepHours: Double?
    let daysSinceLastSession: Int?
    let onRemove: () -> Void
    let onSetDone: () -> Void

    @State private var showingRecInfo = false

    private struct Rec {
        let weight: String; let reps: Int
        let dirLabel: String; let icon: String; let color: Color
    }

    private func bestSet(from prev: ExerciseLog) -> SetEntry? {
        prev.sets
            .filter { $0.done && !$0.weight.isEmpty }
            .max { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }
            ?? prev.sets.first(where: { !$0.weight.isEmpty })
    }

    private func recommendation(from prev: ExerciseLog) -> Rec? {
        guard let best = bestSet(from: prev),
              let prevWeight = Double(best.weight), prevWeight > 0 else { return nil }
        let readiness = WorkoutRecommender.sessionReadiness(
            sleepHours: sleepHours, daysSinceLastSession: daysSinceLastSession
        )
        let step = unit == .kg ? 2.5 : 5.0
        let prevReps = Int(best.reps) ?? 0
        let suggested: Double
        let dirLabel: String; let icon: String; let color: Color; let suggestedReps: Int
        if readiness >= 0.85 {
            suggested = ((prevWeight + step) / step).rounded() * step
            dirLabel = "Progress"; icon = "arrow.up.circle.fill"; color = .green
            suggestedReps = prevReps
        } else if readiness >= 0.65 {
            suggested = prevWeight
            dirLabel = "Maintain"; icon = "equal.circle.fill"; color = .accentColor
            suggestedReps = max(1, prevReps + 1)
        } else {
            suggested = ((prevWeight * 0.9) / step).rounded() * step
            dirLabel = "Recover"; icon = "arrow.down.circle.fill"; color = .orange
            suggestedReps = prevReps
        }
        let weightStr = suggested.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(suggested)) : String(format: "%.1f", suggested)
        return Rec(weight: weightStr, reps: suggestedReps, dirLabel: dirLabel, icon: icon, color: color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName).font(.headline)
                    if let prev = previousLog, let best = bestSet(from: prev) {
                        Text("Last: \(best.weight) \(unit.rawValue) × \(best.reps)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .tint(.red)
            }

            // Recommendation badge
            if let prev = previousLog, let rec = recommendation(from: prev) {
                HStack(spacing: 8) {
                    Image(systemName: rec.icon).foregroundStyle(rec.color)
                    HStack(spacing: 4) {
                        Text(rec.dirLabel).fontWeight(.semibold)
                        Button { showingRecInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingRecInfo) { RecommendationInfoView() }
                        Text("·").fontWeight(.semibold)
                        Text(rec.reps > 0
                             ? "\(rec.weight) \(unit.rawValue) × \(rec.reps)"
                             : "\(rec.weight) \(unit.rawValue)")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(rec.color.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Column headers
            HStack(spacing: 0) {
                Text("Set").font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                Spacer()
                Text(unit.rawValue).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .center)
                Text("Reps").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .center)
                Text("✓").font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .center)
            }

            ForEach(log.sets.indices, id: \.self) { i in
                CustomSetRow(
                    set: Binding(get: { log.sets[i] }, set: { log.sets[i] = $0 }),
                    setNumber: i + 1,
                    canDelete: log.sets.count > 1,
                    onDelete: { log.sets.remove(at: i) },
                    onDone: onSetDone
                )
            }

            HStack {
                Button {
                    let last = log.sets.last
                    log.sets.append(SetEntry(id: UUID(), weight: last?.weight ?? "", reps: last?.reps ?? "", rir: "2", done: false))
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Custom Set Row

private struct CustomSetRow: View {
    @Binding var set: SetEntry
    let setNumber: Int
    let canDelete: Bool
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Set number or delete button
            ZStack {
                if canDelete && !set.done {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("\(setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(set.done ? .tertiary : .secondary)
                }
            }
            .frame(width: 36, alignment: .leading)

            Spacer()

            TextField("0", text: $set.weight)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 80)
                .padding(.vertical, 6)
                .background(set.done ? Color.clear : Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(set.done)

            TextField("0", text: $set.reps)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .padding(.vertical, 6)
                .background(set.done ? Color.clear : Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(set.done)

            Button {
                withAnimation(.spring(duration: 0.2)) { set.done.toggle() }
                if set.done { onDone() }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.done ? .green : Color(.quaternaryLabel))
            }
            .frame(width: 40)
        }
        .padding(.vertical, 4)
        .background(set.done ? Color.green.opacity(0.07) : Color.clear)
    }
}

// MARK: - Exercise Picker Sheet

struct ExercisePickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var searchText = ""

    /// All exercise names: bundled catalog + user exercises + names from past workouts.
    private var allExerciseNames: [String] {
        store.availableExerciseNames
    }

    /// Names seen in past sessions (for a "Recent" section when not searching)
    private var recentNames: [String] {
        store.recentExerciseNames
    }

    private var customNames: [String] {
        store.logbook.customExerciseNames
    }

    private var filtered: [String] {
        let base = searchText.isEmpty
            ? allExerciseNames
            : allExerciseNames.filter { WorkoutLogic.exerciseName($0, matches: searchText) }
        return WorkoutLogic.prioritizedExerciseNames(
            base,
            videos: store.catalog.videos,
            exerciseIndex: store.exerciseIndex
        )
    }

    private var showAddCustom: Bool {
        !searchText.isEmpty &&
        !WorkoutLogic.containsExerciseName(allExerciseNames, matching: searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                // Add custom name if search doesn't match anything
                if showAddCustom {
                    Section {
                        Button {
                            let name = WorkoutLogic.cleanedExerciseName(searchText)
                            store.addCustomExerciseName(name)
                            onSelect(name)
                            dismiss()
                        } label: {
                            Label("Add \"\(WorkoutLogic.cleanedExerciseName(searchText))\"", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                if searchText.isEmpty {
                    // Recent section when no search is active
                    if !recentNames.isEmpty {
                        Section("Recently Used") {
                            ForEach(recentNames, id: \.self) { name in
                                exerciseRow(name)
                            }
                        }
                    }
                    if !customNames.isEmpty {
                        Section("My Exercises") {
                            ForEach(customNames, id: \.self) { name in
                                exerciseRow(name)
                            }
                        }
                    }
                    Section("All Exercises") {
                        ForEach(filtered, id: \.self) { name in
                            exerciseRow(name)
                        }
                    }
                } else {
                    Section {
                        ForEach(filtered, id: \.self) { name in
                            exerciseRow(name)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search or type exercise name")
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func exerciseRow(_ name: String) -> some View {
        Button {
            onSelect(name)
            dismiss()
        } label: {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if store.exerciseIndex[name.lowercased()] != nil {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if store.catalog.videos[name] != nil {
                    Image(systemName: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Custom Workout Picker

struct CustomWorkoutPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sessionWeek = 0
    @State private var showingWorkout = false
    @State private var selectedTemplate: SessionLog? = nil

    private var recentSessions: [SessionLog] {
        Array(store.logbook.sessions.values
            .filter { $0.completed != nil }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
            .prefix(8))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        sessionWeek = Int(Date().timeIntervalSince1970)
                        selectedTemplate = nil
                        showingWorkout = true
                    } label: {
                        Label("Start Fresh", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if !recentSessions.isEmpty {
                    Section("Duplicate a Recent Workout") {
                        ForEach(recentSessions, id: \.self) { session in
                            Button {
                                sessionWeek = Int(Date().timeIntervalSince1970)
                                selectedTemplate = session
                                showingWorkout = true
                            } label: {
                                WorkoutPickerRow(session: session)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("custom_workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingWorkout) {
                CustomWorkoutView(sessionWeek: sessionWeek, template: selectedTemplate, onDone: { dismiss() })
            }
        }
    }
}

private struct WorkoutPickerRow: View {
    let session: SessionLog

    var title: String { WorkoutLogic.sessionDisplayTitle(session) }

    var exerciseCount: Int { session.slotLogs.count }
    var setCount: Int { session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count } }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    if let completed = session.completed {
                        Text(completed, style: .date).font(.caption).foregroundStyle(.secondary)
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text("\(exerciseCount) ex · \(setCount) sets").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
