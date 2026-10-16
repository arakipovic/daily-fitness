import SwiftUI
import Charts

struct WorkoutHistoryView: View {
    @Environment(Store.self) private var store
    @State private var tab: Int = 0
    @State private var showingExporter = false
    @State private var csvData = ""

    var sortedSessions: [SessionLog] {
        store.logbook.sessions.values
            .filter { $0.completed != nil }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    Text("Analytics").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)

                if tab == 0 {
                    AnalyticsView()
                } else {
                    historyView
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("workout_history")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if tab == 1 {
                        Button {
                            csvData = store.exportCSV()
                            showingExporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(sortedSessions.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingExporter) {
                ShareSheet(items: [csvData])
            }
        }
    }

    @ViewBuilder
    private var historyView: some View {
        if sortedSessions.isEmpty {
            ContentUnavailableView(
                "No Workouts Yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Complete a workout to see your history here.")
            )
        } else {
            List {
                ForEach(sortedSessions, id: \.self) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionSummaryRow(session: session)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - Analytics Dashboard

private struct AnalyticsView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    private var bodyweightKg: Double {
        healthKit.recentWeightKg ?? store.resolvedBodyWeightKg
    }
    private var stats: [ExerciseStat] {
        AnalyticsLogic.exerciseStats(from: store.logbook.sessions.values, bodyweightKg: bodyweightKg)
    }
    private var summary: AnalyticsLogic.WorkoutSummary {
        AnalyticsLogic.summary(from: store.logbook.sessions.values, bodyweightKg: bodyweightKg)
    }
    private var activeDays: Int {
        AnalyticsLogic.dailyTrainingLoad(from: store.logbook.sessions.values, bodyweightKg: bodyweightKg, days: 28)
            .filter { $0.workouts > 0 }.count
    }
    private var topPR: ExerciseStat? {
        stats.sorted { $0.estimated1RM > $1.estimated1RM }.first
    }
    private var nutritionSummary: NutritionSummary {
        AnalyticsLogic.nutritionSummary(from: store.logbook.foodLog, days: 28)
    }
    private var proteinTarget: Double { store.logbook.proteinTarget }
    private var fiberTarget: Double   { store.logbook.fiberTarget }

    /// Average discounted active calories per day from the last 14 days of workouts.
    /// Applies the same 30% wearable discount used in NutritionView.
    private var avgDiscountedActiveKcalPerDay: Double {
        guard !healthKit.recentActivities.isEmpty else { return 0 }
        let total = healthKit.recentActivities.reduce(0.0) { $0 + $1.activeCalories }
        return total * 0.7 / 14
    }

    /// Base calorie target + average exercise calories, matching how the daily budget is computed.
    private var effectiveCalorieTarget: Int {
        store.logbook.calorieTarget + Int(avgDiscountedActiveKcalPerDay.rounded())
    }

    private var dailyCalorieDiff: Int {
        Int(nutritionSummary.avgCalories.rounded()) - effectiveCalorieTarget
    }

    /// Calorie-math projection only — weight trend is too noisy (water weight) for a 7-day window.
    private var projectedWeeklyChangeKg: Double? {
        guard nutritionSummary.loggedDays >= 5 else { return nil }
        return Double(dailyCalorieDiff) * 7.0 / 7700.0
    }

    private var bodyFatPct: Double? {
        healthKit.bodyFatPercentage ?? store.latestBodyMeasurement?.bodyFatPercent
    }
    private var avgSleepHours: Double {
        guard !healthKit.weeklySleep.isEmpty else { return 0 }
        return healthKit.weeklySleep.map(\.asleepHours).reduce(0, +) / Double(healthKit.weeklySleep.count)
    }
    private var hasAnyData: Bool {
        !stats.isEmpty || nutritionSummary.loggedDays > 0 || !healthKit.weeklySleep.isEmpty
    }

    var body: some View {
        if !hasAnyData {
            ContentUnavailableView(
                "No Data Yet",
                systemImage: "chart.bar",
                description: Text("Complete workouts, log food, or sync Apple Health to see your analytics.")
            )
        } else {
            List {
                if !stats.isEmpty {
                    Section("Training") {
                        HStack(spacing: 0) {
                            SummaryChip(value: "\(summary.totalWorkouts)", label: "Workouts")
                            Divider().frame(height: 36)
                            SummaryChip(value: "\(summary.totalSets)", label: "Sets")
                            Divider().frame(height: 36)
                            SummaryChip(value: summary.formattedVolume, label: "Volume")
                            Divider().frame(height: 36)
                            SummaryChip(value: "\(activeDays)/28", label: "Active")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                        if let pr = topPR {
                            AnalyticsMetricRow(
                                label: "Best e1RM",
                                value: "\(Int(pr.estimated1RM))kg",
                                detail: "\(pr.name) · \(String(format: "%.1f", pr.bestWeight))kg × \(pr.bestReps)"
                            )
                        }
                        NavigationLink {
                            TrainingDetailView(
                                sessions: Array(store.logbook.sessions.values),
                                bodyweightKg: bodyweightKg
                            )
                        } label: {
                            Label("Charts & records", systemImage: "chart.xyaxis.line")
                                .font(.subheadline)
                        }
                    }
                }

                if nutritionSummary.loggedDays > 0 {
                    Section("Nutrition") {
                        let calDiff = dailyCalorieDiff
                        AnalyticsMetricRow(
                            label: "Avg calories",
                            value: "\(Int(nutritionSummary.avgCalories.rounded())) kcal",
                            detail: "target \(effectiveCalorieTarget) · \(calDiff >= 0 ? "+" : "")\(calDiff)/day"
                        )
                        let proteinDiff = Int(nutritionSummary.avgProtein.rounded()) - Int(proteinTarget)
                        AnalyticsMetricRow(
                            label: "Avg protein",
                            value: "\(Int(nutritionSummary.avgProtein.rounded()))g",
                            detail: "target \(Int(proteinTarget))g · \(proteinDiff >= 0 ? "+" : "")\(proteinDiff)g"
                        )
                        let fiberDiff = Int(nutritionSummary.avgFiber.rounded()) - Int(fiberTarget)
                        AnalyticsMetricRow(
                            label: "Avg fiber",
                            value: "\(Int(nutritionSummary.avgFiber.rounded()))g",
                            detail: "target \(Int(fiberTarget))g · \(fiberDiff >= 0 ? "+" : "")\(fiberDiff)g"
                        )

                        if let weeklyChange = projectedWeeklyChangeKg {
                            NutritionProjectionRow(
                                weeklyChangeKg: weeklyChange,
                                bodyFatPct: bodyFatPct,
                                bodyWeightKg: healthKit.recentWeightKg ?? store.resolvedBodyWeightKg
                            )
                        }

                        NavigationLink {
                            NutritionDetailView(
                                foodLog: store.logbook.foodLog,
                                calorieTarget: effectiveCalorieTarget,
                                proteinTarget: proteinTarget,
                                fiberTarget: fiberTarget
                            )
                        } label: {
                            Label("Charts & trends", systemImage: "fork.knife")
                                .font(.subheadline)
                        }
                    }
                }

                if !healthKit.weeklySleep.isEmpty {
                    Section("Sleep") {
                        AnalyticsMetricRow(
                            label: "7-day average",
                            value: String(format: "%.1fh", avgSleepHours),
                            detail: healthKit.lastNightSleep.map {
                                "Last night: \($0.quality) · \(String(format: "%.1f", $0.asleepHours))h"
                            } ?? "No recent data"
                        )
                        NavigationLink {
                            SleepAnalyticsDetailView(
                                weeklySleep: healthKit.weeklySleep,
                                lastNight: healthKit.lastNightSleep
                            )
                        } label: {
                            Label("Charts & stages", systemImage: "bed.double")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - Training Detail

private struct TrainingDetailView: View {
    let sessions: [SessionLog]
    let bodyweightKg: Double

    @State private var trendMetric: AnalyticsTrendMetric = .volume

    private var weeklyLoad: [WeeklyTrainingLoad] {
        AnalyticsLogic.weeklyTrainingLoad(from: sessions, bodyweightKg: bodyweightKg, weeks: 4)
    }
    private var dailyLoad: [DailyTrainingLoad] {
        AnalyticsLogic.dailyTrainingLoad(from: sessions, bodyweightKg: bodyweightKg, days: 28)
    }
    private var stats: [ExerciseStat] {
        AnalyticsLogic.exerciseStats(from: sessions, bodyweightKg: bodyweightKg)
    }
    private var prStats: [ExerciseStat] {
        Array(stats.sorted { $0.estimated1RM > $1.estimated1RM }.prefix(8))
    }
    private var progressStats: [ExerciseStat] {
        AnalyticsLogic.exerciseProgressCandidates(from: sessions, bodyweightKg: bodyweightKg, limit: 3)
    }
    private var exerciseProgressSeries: [ExerciseProgressSeries] {
        progressStats.compactMap { stat in
            let points = AnalyticsLogic.exerciseProgress(exerciseName: stat.name, from: sessions, bodyweightKg: bodyweightKg)
            return points.isEmpty ? nil : ExerciseProgressSeries(stat: stat, points: points)
        }
    }
    private var exerciseProgressPoints: [ExerciseProgressPoint] {
        exerciseProgressSeries.flatMap { $0.points }
    }
    private var volumeShares: [VolumeShare] {
        AnalyticsLogic.volumeDistribution(from: sessions, bodyweightKg: bodyweightKg, limit: 7)
    }
    private var activeDays: Int { dailyLoad.filter { $0.workouts > 0 }.count }

    var body: some View {
        List {
            Section("Weekly Load") {
                Picker("Metric", selection: $trendMetric) {
                    ForEach(AnalyticsTrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Chart(weeklyLoad) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value(trendMetric.rawValue, trendMetric.value(for: week))
                    )
                    .foregroundStyle(trendMetric.color.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)

                AnalyticsMetricRow(
                    label: "Last 4 weeks",
                    value: trendMetric.summaryValue(for: weeklyLoad),
                    detail: trendMetric.unit
                )
            }

            Section("Consistency (28 days)") {
                Chart(dailyLoad) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Workouts", day.workouts)
                    )
                    .foregroundStyle(day.workouts > 0 ? Color.green.gradient : Color.gray.opacity(0.25).gradient)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 1, 2]) }
                .frame(height: 100)

                AnalyticsMetricRow(
                    label: "Training days",
                    value: "\(activeDays) of 28",
                    detail: "\(dailyLoad.reduce(0) { $0 + $1.workouts }) workouts total"
                )
            }

            if !exerciseProgressSeries.isEmpty {
                Section("Strength Progress") {
                    Chart(exerciseProgressPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", point.estimated1RM)
                        )
                        .foregroundStyle(by: .value("Exercise", point.exerciseName))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", point.estimated1RM)
                        )
                        .foregroundStyle(by: .value("Exercise", point.exerciseName))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 180)

                    ForEach(exerciseProgressSeries) { series in
                        if let latest = series.points.last,
                           let best = series.points.max(by: { $0.estimated1RM < $1.estimated1RM }) {
                            AnalyticsMetricRow(
                                label: series.stat.name,
                                value: "\(Int(latest.estimated1RM))kg e1RM",
                                detail: "Best \(Int(best.estimated1RM))kg · \(formatVolume(series.stat.totalVolume)) total"
                            )
                        }
                    }
                }
            }

            if !volumeShares.isEmpty {
                Section("Volume by Exercise") {
                    Chart(volumeShares) { share in
                        BarMark(
                            x: .value("Volume", share.volumeKg / 1000),
                            y: .value("Exercise", share.name)
                        )
                        .foregroundStyle(Color.purple.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(position: .bottom) }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: max(180, CGFloat(volumeShares.count) * 34))

                    ForEach(volumeShares) { share in
                        AnalyticsMetricRow(
                            label: share.name,
                            value: formatVolume(share.volumeKg),
                            detail: "\(Int((share.percent * 100).rounded()))% · \(share.sets) sets"
                        )
                    }
                }
            }

            Section("Personal Records") {
                ForEach(prStats) { stat in
                    AnalyticsMetricRow(
                        label: stat.name,
                        value: "\(Int(stat.estimated1RM))kg e1RM",
                        detail: "Best set \(String(format: "%.1f", stat.bestWeight))kg × \(stat.bestReps)"
                    )
                }
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
    }

    private func formatVolume(_ kg: Double) -> String {
        kg >= 1000 ? String(format: "%.1ft", kg / 1000) : "\(Int(kg))kg"
    }
}

// MARK: - Nutrition Detail

private struct NutritionDetailView: View {
    let foodLog: [FoodEntry]
    let calorieTarget: Int
    let proteinTarget: Double
    let fiberTarget: Double

    private var summary: NutritionSummary {
        AnalyticsLogic.nutritionSummary(from: foodLog, days: 28)
    }
    private var daily: [DailyNutrition] {
        AnalyticsLogic.dailyNutrition(from: foodLog, days: 28)
    }

    var body: some View {
        List {
            Section("Calories (28 days)") {
                Chart {
                    ForEach(daily) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("kcal", day.calories)
                        )
                        .foregroundStyle(day.calories > calorieTarget ? Color.red.opacity(0.7).gradient
                                         : day.calories > 0 ? Color.orange.gradient
                                         : Color.gray.opacity(0.2).gradient)
                        .cornerRadius(2)
                    }
                    if calorieTarget > 0 {
                        RuleMark(y: .value("Target", calorieTarget))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("target").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)

                let calDiff = Int(summary.avgCalories.rounded()) - calorieTarget
                AnalyticsMetricRow(
                    label: "Avg calories",
                    value: "\(Int(summary.avgCalories.rounded())) kcal/day",
                    detail: "target \(calorieTarget) · \(calDiff >= 0 ? "+" : "")\(calDiff)/day · \(summary.loggedDays)/28 days"
                )
                let proteinDiff = Int(summary.avgProtein.rounded()) - Int(proteinTarget)
                AnalyticsMetricRow(
                    label: "Avg protein",
                    value: "\(Int(summary.avgProtein.rounded()))g/day",
                    detail: "target \(Int(proteinTarget))g · \(proteinDiff >= 0 ? "+" : "")\(proteinDiff)g · carbs \(Int(summary.avgCarbs.rounded()))g"
                )
                let fiberDiff = Int(summary.avgFiber.rounded()) - Int(fiberTarget)
                AnalyticsMetricRow(
                    label: "Avg fiber",
                    value: "\(Int(summary.avgFiber.rounded()))g/day",
                    detail: "target \(Int(fiberTarget))g · \(fiberDiff >= 0 ? "+" : "")\(fiberDiff)g"
                )
            }
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
    }
}

// MARK: - Sleep Detail

private struct SleepAnalyticsDetailView: View {
    let weeklySleep: [HealthKitManager.SleepSummary]
    let lastNight: HealthKitManager.SleepSummary?

    private var avgHours: Double {
        guard !weeklySleep.isEmpty else { return 0 }
        return weeklySleep.map(\.asleepHours).reduce(0, +) / Double(weeklySleep.count)
    }

    var body: some View {
        List {
            Section("7-Day Sleep") {
                Chart(weeklySleep) { night in
                    BarMark(
                        x: .value("Date", night.date, unit: .day),
                        y: .value("Hours", night.asleepHours)
                    )
                    .foregroundStyle(night.asleepHours >= 7 ? Color.indigo.gradient : Color.orange.opacity(0.7).gradient)
                    .cornerRadius(3)

                    RuleMark(y: .value("Goal", 7.0))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 140)

                AnalyticsMetricRow(
                    label: "Average",
                    value: String(format: "%.1fh", avgHours),
                    detail: "\(weeklySleep.count) nights tracked · target 7–9h"
                )
            }

            if let last = lastNight {
                Section("Last Night") {
                    AnalyticsMetricRow(
                        label: "Total sleep",
                        value: String(format: "%.1fh", last.asleepHours),
                        detail: last.quality
                    )
                    if last.hasStages {
                        AnalyticsMetricRow(
                            label: "Deep",
                            value: String(format: "%.1fh", last.deepHours),
                            detail: "Most restorative"
                        )
                        AnalyticsMetricRow(
                            label: "REM",
                            value: String(format: "%.1fh", last.remHours),
                            detail: "Memory & learning"
                        )
                        AnalyticsMetricRow(
                            label: "Core",
                            value: String(format: "%.1fh", last.coreHours),
                            detail: "Light NREM"
                        )
                    }
                }
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
    }
}

private enum AnalyticsTrendMetric: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case sets = "Sets"
    case workouts = "Workouts"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .volume: return .blue
        case .sets: return .orange
        case .workouts: return .green
        }
    }

    var unit: String {
        switch self {
        case .volume: return "tonnes"
        case .sets: return "sets"
        case .workouts: return "workouts"
        }
    }

    func value(for week: WeeklyTrainingLoad) -> Double {
        switch self {
        case .volume: return week.volumeTonnes
        case .sets: return Double(week.sets)
        case .workouts: return Double(week.workouts)
        }
    }

    func summaryValue(for weeks: [WeeklyTrainingLoad]) -> String {
        switch self {
        case .volume:
            let tonnes = weeks.reduce(0) { $0 + $1.volumeTonnes }
            return String(format: "%.1ft", tonnes)
        case .sets:
            return "\(weeks.reduce(0) { $0 + $1.sets })"
        case .workouts:
            return "\(weeks.reduce(0) { $0 + $1.workouts })"
        }
    }
}

private struct ExerciseProgressSeries: Identifiable {
    var id: String { stat.name }
    let stat: ExerciseStat
    let points: [ExerciseProgressPoint]
}

private struct NutritionProjectionRow: View {
    let weeklyChangeKg: Double
    let bodyFatPct: Double?
    let bodyWeightKg: Double

    private var isLosing: Bool { weeklyChangeKg < 0 }
    private var absChange: Double { abs(weeklyChangeKg) }

    // Fat fraction: ~80% of deficit loss is fat with good training; ~50% of surplus gain is fat
    private var weeklyFatChangeKg: Double {
        weeklyChangeKg * (isLosing ? 0.80 : 0.50)
    }
    private var weeklyFatPctChange: Double? {
        guard bodyFatPct != nil, bodyWeightKg > 0 else { return nil }
        return weeklyFatChangeKg / bodyWeightKg * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isLosing ? "arrow.down.circle.fill" : absChange < 0.05 ? "equal.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(isLosing ? .green : absChange < 0.05 ? .secondary : .orange)
                Text("Projected rate")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            if absChange < 0.05 {
                Text("Roughly maintenance — weight stable")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text("\(isLosing ? "Losing" : "Gaining") ~\(String(format: "%.2f", absChange)) kg/week")
                        .font(.caption).fontWeight(.medium)
                    if let bfChange = weeklyFatPctChange {
                        Text("·")
                            .font(.caption).foregroundStyle(.tertiary)
                        Text("\(bfChange < 0 ? "" : "+")\(String(format: "%.2f", bfChange))% body fat/week")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Estimated from avg calorie intake vs effective daily target (base + exercise).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct AnalyticsMetricRow: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct SummaryChip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - History rows & detail

private struct SessionSummaryRow: View {
    let session: SessionLog

    var setsCompleted: Int {
        session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    var duration: String? {
        guard let start = session.started, let end = session.completed else { return nil }
        let mins = Int(end.timeIntervalSince(start) / 60)
        guard mins > 0 else { return nil }
        return "\(mins) min"
    }

    var title: String { WorkoutLogic.sessionDisplayTitle(session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let d = duration {
                    Text(d)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(session.completed!, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(setsCompleted) sets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SessionDetailView: View {
    let session: SessionLog
    @Environment(Store.self) private var store

    @State private var editableSession: SessionLog
    @State private var isEditing = false
    @State private var showingDuplicate = false
    @State private var duplicateWeek = 0
    @State private var editableDate: Date
    @State private var editableDurationMinutes: Int

    init(session: SessionLog) {
        self.session = session
        _editableSession = State(initialValue: session)
        _editableDate = State(initialValue: session.completed ?? Date())
        if let start = session.started, let end = session.completed {
            _editableDurationMinutes = State(initialValue: max(5, Int(end.timeIntervalSince(start) / 60)))
        } else {
            _editableDurationMinutes = State(initialValue: 60)
        }
    }

    var sortedLogs: [(String, ExerciseLog)] {
        (isEditing ? editableSession : session).slotLogs.sorted { $0.key < $1.key }
    }

    var navTitle: String { WorkoutLogic.sessionDisplayTitle(session) }

    private var durationString: String? {
        guard let start = session.started, let end = session.completed else { return nil }
        let mins = Int(end.timeIntervalSince(start) / 60)
        guard mins > 0 else { return nil }
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins) min"
    }

    private var setsCompleted: Int {
        session.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    private var estimatedKcal: Int? {
        WorkoutLogic.estimatedKcalBurned(session: session, weightKg: store.resolvedBodyWeightKg)
    }

    var body: some View {
        List {
            if isEditing {
                Section("Workout Details") {
                    DatePicker("Date", selection: $editableDate, displayedComponents: [.date, .hourAndMinute])
                    Stepper("\(editableDurationMinutes) min", onIncrement: {
                        editableDurationMinutes = min(editableDurationMinutes + 5, 600)
                    }, onDecrement: {
                        editableDurationMinutes = max(editableDurationMinutes - 5, 5)
                    })
                }
            } else {
                Section {
                    if let d = durationString {
                        LabeledContent("Duration", value: d)
                    }
                    LabeledContent("Sets completed", value: "\(setsCompleted)")
                    if let kcal = estimatedKcal {
                        LabeledContent("Est. calories") {
                            Text("~\(kcal) kcal")
                        }
                    }
                }
            }
            ForEach(sortedLogs, id: \.0) { label, log in
                Section(log.exerciseName) {
                    ForEach(log.sets.indices, id: \.self) { i in
                        if isEditing {
                            editableSetRow(label: label, index: i)
                        } else {
                            readOnlySetRow(set: log.sets[i], index: i)
                        }
                    }
                    if !log.note.isEmpty {
                        Text(log.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isEditing {
                        Button("Cancel") {
                            editableSession = session
                            editableDate = session.completed ?? Date()
                            editableDurationMinutes = {
                                guard let s = session.started, let e = session.completed else { return 60 }
                                return max(5, Int(e.timeIntervalSince(s) / 60))
                            }()
                            isEditing = false
                        }
                        .foregroundStyle(.red)
                        Button("Save") {
                            editableSession.completed = editableDate
                            editableSession.started = Calendar.current.date(
                                byAdding: .minute, value: -editableDurationMinutes, to: editableDate
                            )
                            store.updateSession(editableSession)
                            isEditing = false
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button {
                            duplicateWeek = Int(Date().timeIntervalSince1970)
                            showingDuplicate = true
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button("Edit") { isEditing = true }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingDuplicate) {
            CustomWorkoutView(sessionWeek: duplicateWeek, template: session)
        }
    }

    @ViewBuilder
    private func readOnlySetRow(set: SetEntry, index: Int) -> some View {
        HStack {
            Text("Set \(index + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if !set.weight.isEmpty {
                Text(set.weight)
                    .font(.subheadline.weight(.medium))
                Text("×")
                    .foregroundStyle(.secondary)
            }
            Text(set.reps.isEmpty ? "—" : set.reps)
                .font(.subheadline.weight(.medium))
            if !set.rir.isEmpty {
                Text("RIR \(set.rir)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func editableSetRow(label: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Set \(index + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Spacer()
            TextField("kg", text: Binding(
                get: { editableSession.slotLogs[label]?.sets[safe: index]?.weight ?? "" },
                set: { v in
                    guard editableSession.slotLogs[label] != nil,
                          editableSession.slotLogs[label]!.sets.indices.contains(index) else { return }
                    editableSession.slotLogs[label]!.sets[index].weight = v
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

            Text("×").foregroundStyle(.secondary)

            TextField("reps", text: Binding(
                get: { editableSession.slotLogs[label]?.sets[safe: index]?.reps ?? "" },
                set: { v in
                    guard editableSession.slotLogs[label] != nil,
                          editableSession.slotLogs[label]!.sets.indices.contains(index) else { return }
                    editableSession.slotLogs[label]!.sets[index].reps = v
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Close Button

private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}
