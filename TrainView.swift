import SwiftUI

struct TrainView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(GlobalActions.self) private var global
    @State private var selectedWeek: Int = 1
    @State private var showingCustomWorkout = false
    @State private var customWorkoutWeek: Int = 0
    @State private var duplicateTemplate: SessionLog? = nil

    var program: TrainingProgram? {
        store.catalog.programs.first { $0.id == store.logbook.selectedProgramID }
    }

    var recentSessions: [SessionLog] {
        Array(store.logbook.sessions.values
            .filter { $0.completed != nil }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
            .prefix(5))
    }

    var body: some View {
        NavigationStack {
            if let program {
                let next = store.nextSession(for: program)
                ScrollView {
                    VStack(spacing: 20) {
                        if !recentSessions.isEmpty {
                            recentWorkoutsSection
                        }

                        WeekPickerView(
                            totalWeeks: program.weeks,
                            selectedWeek: $selectedWeek,
                            nextWeek: next?.week
                        )

                        VStack(spacing: 12) {
                            ForEach(program.days) { pd in
                                let key = store.sessionKey(programID: program.id, week: selectedWeek, day: pd.number)
                                let session = store.logbook.sessions[key]
                                let isNext = next.map { $0.week == selectedWeek && $0.day == pd.number } == true

                                NavigationLink {
                                    let key = store.sessionKey(programID: program.id, week: selectedWeek, day: pd.number)
                                    WorkoutDayView(programID: program.id, week: selectedWeek, day: pd,
                                                   existingSession: store.logbook.sessions[key])
                                } label: {
                                    DayCard(
                                        program: program,
                                        day: pd,
                                        session: session,
                                        isNext: isNext,
                                        isCompleted: session?.completed != nil,
                                        readiness: isNext && session?.completed == nil
                                            ? WorkoutRecommender.sessionReadiness(
                                                sleepHours: healthKit.lastNightSleep?.asleepHours,
                                                daysSinceLastSession: store.daysSinceLastSession()
                                              )
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // Custom workout card
                            Button {
                                global.showingCustomWorkout = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.tertiarySystemBackground))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "plus")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Custom Workout")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Add exercises freely, no program needed")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .navigationTitle(program.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { global.showingCustomWorkout = true } label: {
                            Image(systemName: "plus")
                        }
                        Button { global.showingHistory = true } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                        Button { global.showingSettings = true } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
                .onAppear {
                    if let next = store.nextSession(for: program) {
                        selectedWeek = next.week
                    } else {
                        selectedWeek = max(1, program.weeks)
                    }
                }
                .fullScreenCover(isPresented: $showingCustomWorkout) {
                    CustomWorkoutView(sessionWeek: customWorkoutWeek, template: duplicateTemplate)
                }
            } else {
                noProgramView
                    .navigationTitle("Train")
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button { global.showingCustomWorkout = true } label: {
                                Image(systemName: "plus")
                            }
                            Button { global.showingHistory = true } label: {
                                Image(systemName: "chart.bar.xaxis")
                            }
                            Button { global.showingSettings = true } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
                    .fullScreenCover(isPresented: $showingCustomWorkout) {
                        CustomWorkoutView(sessionWeek: customWorkoutWeek, template: duplicateTemplate)
                    }
            }
        }
    }

    // MARK: - No program view

    private var noProgramView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                    Text("Choose a Program")
                        .font(.title2.weight(.bold))
                    Text("Select a structured program or start a custom workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(store.catalog.programs) { prog in
                        Button {
                            store.logbook.selectedProgramID = prog.id
                            store.saveLogbook()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(prog.name).font(.headline).foregroundStyle(.primary)
                                    Text(prog.title).font(.caption).foregroundStyle(.secondary)
                                    Text("\(prog.weeks) weeks · \(prog.daysPerWeek) days/week")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Divider().padding(.horizontal, 40)

                Button {
                    global.showingCustomWorkout = true
                } label: {
                    Label("Start Custom Workout", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Recent workouts section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Workouts")
                    .font(.headline)
                Spacer()
                Button("See All") { global.showingHistory = true }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentSessions, id: \.self) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            RecentSessionCard(session: session)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                duplicateTemplate = session
                                customWorkoutWeek = Int(Date().timeIntervalSince1970)
                                showingCustomWorkout = true
                            } label: {
                                Label("Duplicate Workout", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

}

// MARK: - Recent Session Card

private struct RecentSessionCard: View {
    let session: SessionLog

    var title: String { WorkoutLogic.sessionDisplayTitle(session) }

    var setsCompleted: Int {
        session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if let completed = session.completed {
                Text(completed, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(setsCompleted) sets")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 150, height: 100)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Week Picker

private struct WeekPickerView: View {
    let totalWeeks: Int
    @Binding var selectedWeek: Int
    let nextWeek: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...max(1, totalWeeks), id: \.self) { week in
                        Button {
                            withAnimation(.spring(duration: 0.3)) { selectedWeek = week }
                        } label: {
                            VStack(spacing: 1) {
                                Text("WK")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(week)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .frame(width: 52, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedWeek == week ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(selectedWeek == week ? .white : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        week == nextWeek && selectedWeek != week
                                            ? Color.accentColor.opacity(0.5)
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .id(week)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: selectedWeek) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}

// MARK: - Day Card

private struct DayCard: View {
    let program: TrainingProgram
    let day: ProgramDay
    let session: SessionLog?
    let isNext: Bool
    let isCompleted: Bool
    var readiness: Double? = nil

    private var totalSets: Int { day.exercises.reduce(0) { $0 + $1.sets } }
    private var doneSets: Int {
        session?.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count } ?? 0
    }
    private var inProgress: Bool { session != nil && !isCompleted && doneSets > 0 }

    private var dayFocus: String {
        program.dayFocusTitle(for: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconBg)
                        .frame(width: 38, height: 38)
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(dayFocus)
                        .font(.headline)
                    Text(exercisePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(day.exercises.count) ex · \(totalSets) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let completed = session?.completed {
                        Text(completed, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if inProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(doneSets), total: Double(max(1, totalSets)))
                        .tint(.accentColor)
                    Text("\(doneSets) / \(totalSets) sets done · tap to continue")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            } else if isNext && !isCompleted {
                if let r = readiness {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(WorkoutRecommendation.color(for: r))
                            .frame(width: 7, height: 7)
                        Text("Readiness: \(WorkoutRecommendation.label(for: r))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorder, lineWidth: 1.5)
                )
        )
    }

    private var cardBg: Color {
        if isCompleted { return Color.green.opacity(0.06) }
        if isNext { return Color.accentColor.opacity(0.07) }
        return Color(.secondarySystemBackground)
    }

    private var cardBorder: Color {
        isNext && !isCompleted ? Color.accentColor.opacity(0.3) : Color.clear
    }

    private var iconName: String {
        if isCompleted { return "checkmark" }
        if isNext || inProgress { return "play.fill" }
        return "lock.fill"
    }

    private var iconBg: Color {
        if isCompleted { return Color.green.opacity(0.15) }
        if isNext || inProgress { return Color.accentColor.opacity(0.15) }
        return Color(.tertiarySystemBackground)
    }

    private var iconColor: Color {
        if isCompleted { return .green }
        if isNext || inProgress { return .accentColor }
        return Color(.quaternaryLabel)
    }

    private var exercisePreview: String {
        day.exercises.prefix(4).map(\.name).joined(separator: " · ")
    }
}


