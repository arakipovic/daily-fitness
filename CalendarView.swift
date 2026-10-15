import SwiftUI

// MARK: - Calendar Tab

struct CalendarView: View {
    @Environment(Store.self) private var store
    @State private var displayedMonth = Date()
    @State private var selectedDay: IdentifiableDate? = nil

    private var calendar: Calendar { .current }

    private var sessions: [SessionLog] {
        store.logbook.sessions.values.filter { $0.completed != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    monthHeader
                        .padding(.horizontal)
                        .padding(.top, 8)
                    weekdayRow
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                    calendarGrid
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                    legend
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedDay) { item in
                CalendarDayDetailView(date: item.date)
            }
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month))
        }
    }

    // MARK: Weekday labels (Mon … Sun)

    private var weekdayRow: some View {
        let symbols = shortWeekdaySymbols()
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func shortWeekdaySymbols() -> [String] {
        var syms = calendar.veryShortWeekdaySymbols
        // Rotate so the calendar's firstWeekday is first (1-indexed, convert to 0-indexed)
        let offset = calendar.firstWeekday - 1
        return Array(syms[offset...] + syms[..<offset])
    }

    // MARK: Day grid

    private var calendarGrid: some View {
        let dates = CalendarLogic.datesInMonth(containing: displayedMonth, calendar: calendar)
        let offset = CalendarLogic.weekdayOffset(for: displayedMonth, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            // Leading empty cells
            ForEach(0..<offset, id: \.self) { _ in
                Color.clear.frame(height: 52)
            }
            // Day cells
            ForEach(dates, id: \.self) { date in
                DayCell(
                    date: date,
                    hasWorkout: CalendarLogic.hasCompletedSession(in: sessions, on: date, calendar: calendar),
                    hasFood: !NutritionLogic.entries(store.logbook.foodLog, on: date, calendar: calendar).isEmpty,
                    hasMeasurement: store.logbook.bodyMeasurements.contains { calendar.isDate($0.date, inSameDayAs: date) }
                )
                .onTapGesture {
                    selectedDay = IdentifiableDate(date: date)
                }
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 20) {
            LegendDot(color: .green, label: "Workout")
            LegendDot(color: .orange, label: "Food logged")
            LegendDot(color: .purple, label: "Measurements")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let hasWorkout: Bool
    let hasFood: Bool
    let hasMeasurement: Bool

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isFuture: Bool { date > Date() }
    private var dayNumber: Int { calendar.component(.day, from: date) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                }
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (isFuture ? Color.secondary.opacity(0.4) : Color.primary))
            }
            .frame(height: 32)

            HStack(spacing: 3) {
                if hasWorkout    { Dot(color: .green) }
                if hasFood       { Dot(color: .orange) }
                if hasMeasurement { Dot(color: .purple) }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hasWorkout || hasFood || hasMeasurement ? Color(.systemFill) : Color.clear)
        )
    }
}

private struct Dot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

// MARK: - Day Detail Sheet

struct CalendarDayDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var showingFoodLog = false

    private var calendar: Calendar { .current }

    private var sessions: [SessionLog] {
        CalendarLogic.completedSessions(
            in: store.logbook.sessions.values.filter { $0.completed != nil },
            on: date,
            calendar: calendar
        )
    }

    private var foodEntries: [FoodEntry] {
        NutritionLogic.entries(store.logbook.foodLog, on: date, calendar: calendar)
    }

    private var measurements: [BodyMeasurement] {
        store.logbook.bodyMeasurements.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private var totalCalories: Int { NutritionLogic.totalCalories(foodEntries) }
    private var totalProtein: Double { NutritionLogic.totalProtein(foodEntries) }

    var body: some View {
        NavigationStack {
            List {
                // Workouts
                if sessions.isEmpty {
                    Section("Workout") {
                        Label("No workout logged", systemImage: "figure.strengthtraining.traditional")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section("Workout") {
                        ForEach(sessions, id: \.self) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                WorkoutSessionRow(session: session)
                            }
                        }
                    }
                }

                // Food log
                Section {
                    if foodEntries.isEmpty {
                        Label("No food logged", systemImage: "fork.knife")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(totalCalories) kcal")
                                    .font(.headline)
                                Text("P \(String(format: "%.0f", totalProtein))g · \(foodEntries.count) entries")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        ForEach(foodEntries.prefix(5)) { entry in
                            HStack {
                                Text(entry.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.calories) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if foodEntries.count > 5 {
                            Text("+\(foodEntries.count - 5) more entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showingFoodLog = true
                    } label: {
                        Label(foodEntries.isEmpty ? "Add food for this day" : "Edit food log",
                              systemImage: foodEntries.isEmpty ? "plus" : "pencil")
                    }
                } header: {
                    Text("Food")
                }

                // Measurements
                if !measurements.isEmpty {
                    Section("Body Measurements") {
                        ForEach(measurements) { m in
                            MeasurementSummaryRow(measurement: m)
                        }
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.day().month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFoodLog) {
                FoodLogSheetWrapper(date: date)
            }
        }
    }
}

// Wraps FoodLogView in its own NavigationStack for sheet presentation
private struct FoodLogSheetWrapper: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date

    var body: some View {
        NavigationStack {
            FoodLogView(initialDate: date)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct WorkoutSessionRow: View {
    let session: SessionLog

    var setsCompleted: Int {
        session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    var duration: String? {
        guard let start = session.started, let end = session.completed else { return nil }
        let mins = Int(end.timeIntervalSince(start) / 60)
        return mins > 0 ? "\(mins) min" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(WorkoutLogic.sessionDisplayTitle(session))
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                Text("\(setsCompleted) sets")
                if let d = duration {
                    Text("·").foregroundStyle(.tertiary)
                    Text(d)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct MeasurementSummaryRow: View {
    let measurement: BodyMeasurement

    var chips: [(String, Double)] {
        var result: [(String, Double)] = []
        if let v = measurement.waistCm      { result.append(("Waist",   v)) }
        if let v = measurement.chestCm      { result.append(("Chest",   v)) }
        if let v = measurement.hipsCm       { result.append(("Hips",    v)) }
        if let v = measurement.thighsCm     { result.append(("Thighs",  v)) }
        if let v = measurement.armsCm       { result.append(("Arms",    v)) }
        if let v = measurement.neckCm       { result.append(("Neck",    v)) }
        if let v = measurement.bodyFatPercent { result.append(("Body fat", v)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(chips, id: \.0) { name, value in
                        VStack(spacing: 1) {
                            Text(name == "Body fat" ? "\(String(format: "%.1f", value))%" : "\(String(format: "%.1f", value))cm")
                                .font(.caption.weight(.semibold))
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Identifiable Date wrapper

struct IdentifiableDate: Identifiable {
    let id: TimeInterval
    let date: Date
    init(date: Date) { self.date = date; self.id = date.timeIntervalSinceReferenceDate }
}
