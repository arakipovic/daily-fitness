import SwiftUI
import Charts

struct HealthView: View {
    @Environment(HealthKitManager.self) private var hk
    @Environment(Store.self) private var store
    @Environment(GlobalActions.self) private var global

    private var todayCaloriesEaten: Int {
        NutritionLogic.totalCalories(
            NutritionLogic.entries(store.logbook.foodLog, on: Date())
        )
    }

    private var recentActivityItems: [HealthActivityItem] {
        HealthLogic.recentActivityItems(
            appSessions: Array(store.logbook.sessions.values),
            appleHealthItems: hk.recentActivities.map { activity in
                HealthActivityItem(
                    id: "health|\(activity.id.uuidString)",
                    source: .appleHealth,
                    sessionKey: nil,
                    title: activity.displayName,
                    date: activity.startDate,
                    systemImage: activity.systemImage,
                    detail: activity.durationString,
                    metric: activity.activeCalories > 0 ? "\(Int(activity.activeCalories)) kcal" : nil
                )
            }
        )
    }

    var body: some View {
        NavigationStack {
            if hk.authorizationStatus == .notDetermined {
                grantAccessView
            } else {
                List {
                    activitiesSection
                    sleepSection
                    heartSection
                    weightSection
                    measurementsSection
                }
                .navigationTitle("Health")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { quickActionsToolbar }
                .task { await refreshHealthData() }
                .refreshable { await refreshHealthData() }
            }
        }
    }

    @MainActor
    private func refreshHealthData() async {
        await hk.fetchAll()
        store.rebuildExerciseIndex()
    }

    // MARK: Grant Access

    @ToolbarContentBuilder
    private var quickActionsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button { global.showingScanner = true } label: {
                    Label("Add Food", systemImage: "barcode.viewfinder")
                }
                Button { global.showingCustomWorkout = true } label: {
                    Label("Add Workout", systemImage: "figure.strengthtraining.traditional")
                }
            } label: {
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

    private var grantAccessView: some View {
        ContentUnavailableView {
            Label("Connect Apple Health", systemImage: "heart.fill")
        } description: {
            Text("Allow DailyFitness to read your steps, sleep, and body weight from the Health app.")
        } actions: {
            Button("Grant Access") {
                Task { await hk.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Health")
        .toolbar { quickActionsToolbar }
    }

    // MARK: Activities

    private var activitiesSection: some View {
        Section {
            stepsOverview
            if !hk.weeklySteps.isEmpty {
                weeklyStepsChart
            }

            activeEnergyBudget

            if !recentActivityItems.isEmpty {
                Text("Recent Activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(recentActivityItems) { item in
                    recentActivityRow(item)
                }
            }
        } header: {
            Label("Activities", systemImage: "figure.mixed.cardio")
        }
    }

    @ViewBuilder
    private func recentActivityRow(_ item: HealthActivityItem) -> some View {
        if let key = item.sessionKey, let session = store.completedSessionIndex[key] {
            NavigationLink {
                SessionDetailView(session: session)
            } label: {
                recentActivityRowContent(item)
            }
        } else {
            recentActivityRowContent(item)
        }
    }

    private func recentActivityRowContent(_ item: HealthActivityItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(recentActivityColor(for: item).opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(recentActivityColor(for: item))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let detail = item.detail {
                    Text(detail).font(.subheadline.weight(.medium))
                }
                if let metric = item.metric {
                    Text(metric)
                        .font(.caption)
                        .foregroundStyle(recentActivityMetricColor(for: item))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func recentActivityColor(for item: HealthActivityItem) -> Color {
        switch item.source {
        case .inApp: return .blue
        case .appleHealth: return .accentColor
        }
    }

    private func recentActivityMetricColor(for item: HealthActivityItem) -> Color {
        switch item.source {
        case .inApp: return .secondary
        case .appleHealth: return .orange
        }
    }

    private var stepsOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hk.todaySteps >= 8000 ? .green : Color.accentColor)
                Text(Int(hk.todaySteps).formatted())
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("steps today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let goal: Double = 8000
            ProgressView(value: min(hk.todaySteps, goal), total: goal)
                .tint(hk.todaySteps >= goal ? .green : .accentColor)
            HStack {
                Text(hk.todaySteps >= goal ? "Goal reached" : "\(Int(goal - hk.todaySteps).formatted()) to go")
                    .font(.caption)
                    .foregroundStyle(hk.todaySteps >= goal ? .green : .secondary)
                Spacer()
                Text("Goal: \(Int(goal).formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var weeklyStepsChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 Days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(hk.weeklySteps) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Steps", day.steps)
                )
                .foregroundStyle(day.steps >= 8000 ? Color.green : Color.accentColor)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 120)
        }
    }

    // MARK: Sleep

    @ViewBuilder
    private var sleepSection: some View {
        Section {
            if let sleep = hk.lastNightSleep {
                NavigationLink { SleepDetailView() } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", sleep.asleepHours))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("hrs asleep")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(sleep.quality)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(sleepQualityColor(sleep.quality))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(sleepQualityColor(sleep.quality).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        // Bedtime → wake time
                        if let wake = sleep.wakeTime {
                            HStack(spacing: 5) {
                                Image(systemName: "moon.zzz").foregroundStyle(.indigo).font(.caption)
                                Text(sleep.date, style: .time).font(.caption)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Image(systemName: "sunrise").foregroundStyle(.orange).font(.caption)
                                Text(wake, style: .time).font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }

                        if sleep.inBedDuration > sleep.asleepDuration {
                            HStack(spacing: 16) {
                                sleepStat(label: "In Bed", hours: sleep.inBedHours)
                                sleepStat(label: "Asleep", hours: sleep.asleepHours)
                                sleepStat(label: "Efficiency", hours: -1,
                                          pct: sleep.inBedDuration > 0
                                            ? Int(sleep.asleepDuration / sleep.inBedDuration * 100)
                                            : nil)
                            }
                        }

                        // Compact stage proportion bar
                        if sleep.hasStages {
                            let total = sleep.asleepDuration
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    if sleep.coreDuration > 0 {
                                        Color.blue.frame(width: geo.size.width * CGFloat(sleep.coreDuration / total))
                                    }
                                    if sleep.deepDuration > 0 {
                                        Color.indigo.frame(width: geo.size.width * CGFloat(sleep.deepDuration / total))
                                    }
                                    if sleep.remDuration > 0 {
                                        Color.purple.frame(width: geo.size.width * CGFloat(sleep.remDuration / total))
                                    }
                                    let accounted = sleep.coreDuration + sleep.deepDuration + sleep.remDuration
                                    if accounted < total {
                                        Color(.systemFill).frame(width: geo.size.width * CGFloat((total - accounted) / total))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .frame(height: 10)
                            HStack(spacing: 12) {
                                compactStageLegend(color: .blue,   label: "Core", hours: sleep.coreHours)
                                compactStageLegend(color: .indigo, label: "Deep", hours: sleep.deepHours)
                                compactStageLegend(color: .purple, label: "REM",  hours: sleep.remHours)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No sleep data found for last night")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if let bpm = hk.restingHeartRateBPM {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(bpm)) bpm").font(.title2.weight(.bold))
                        Text("Resting heart rate").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "heart.fill").font(.title2).foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("Sleep", systemImage: "moon.fill")
        }
    }

    private func compactStageLegend(color: Color, label: String, hours: Double) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(String(format: "%.1fh", hours))").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func sleepStat(label: String, hours: Double, pct: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pct {
                Text("\(pct)%").font(.subheadline.weight(.semibold))
            } else {
                Text(String(format: "%.1fh", hours)).font(.subheadline.weight(.semibold))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sleepQualityColor(_ quality: String) -> Color {
        switch quality {
        case "Good": return .green
        case "OK":   return .yellow
        case "Fair": return .orange
        default:     return .red
        }
    }

    // MARK: Heart

    @ViewBuilder
    private var heartSection: some View {
        let hasHRV = hk.heartRateVariabilityMs != nil
        if hasHRV {
            Section {
                if let hrv = hk.heartRateVariabilityMs {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.0f ms", hrv)).font(.title2.weight(.bold))
                            Text("Heart rate variability (HRV)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(.pink)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Label("Heart", systemImage: "heart")
            }
        }
    }

    // MARK: Calorie Budget

    private var activeEnergyBudget: some View {
        let target  = store.logbook.calorieTarget
        let burned  = Int(hk.activeEnergyToday)
        let eaten   = todayCaloriesEaten
        let budget  = target + burned
        let remaining = budget - eaten
        let fraction  = budget > 0 ? min(Double(eaten) / Double(budget), 1.0) : 0

        return VStack(spacing: 10) {
            HStack {
                Label("Calorie Budget", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }

            budgetRow(label: "Daily target",      icon: "target",       value: "\(target) kcal",    color: .primary)
            budgetRow(label: "Activity burned",   icon: "flame.fill",   value: "+\(burned) kcal",   color: .orange)
            budgetRow(label: "Food eaten",        icon: "fork.knife",   value: "\(eaten) kcal",     color: .primary)
            Divider()
            HStack {
                Text("Remaining")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(remaining) kcal")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(remaining >= 0 ? .green : .red)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fraction >= 1 ? Color.red : Color.orange)
                        .frame(width: geo.size.width * fraction, height: 8)
                        .animation(.spring(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 8)
            Text("\(eaten) of \(budget) kcal consumed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func budgetRow(label: String, icon: String, value: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(color == .primary ? Color.primary : color)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color == .primary ? Color.primary : color)
        }
    }

    // MARK: Body Composition

    @ViewBuilder
    private var weightSection: some View {
        let hasAny = hk.recentWeightKg != nil || hk.bodyFatPercentage != nil || hk.waistCircumferenceCm != nil
        Section {
            if !hasAny {
                Text("No body composition data found. Log weight, body fat, or waist in the Apple Health app.")
                    .foregroundStyle(.secondary).font(.subheadline)
            }

            // --- Weight ---
            if let kg = hk.recentWeightKg {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "scalemass.fill").foregroundStyle(.blue)
                        Text(String(format: "%.1f kg", kg))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("weight").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if let avg = hk.sevenDayAverageKg {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f kg", avg)).font(.subheadline.weight(.semibold))
                                Text("7-day avg").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if hk.weeklyWeightKg.count >= 2 {
                        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
                        let source = hk.weeklyWeightKg.filter { $0.date >= cutoff }.count >= 2
                            ? hk.weeklyWeightKg.filter { $0.date >= cutoff }
                            : hk.weeklyWeightKg
                        measurementChart(
                            data: source.map { HealthKitManager.DayMeasurement(date: $0.date, value: $0.weightKg) },
                            color: .blue, unit: "kg", padding: 1
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            // --- Body Fat ---
            if let bf = hk.bodyFatPercentage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "figure.arms.open").foregroundStyle(.teal)
                        Text(String(format: "%.1f%%", bf))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("body fat").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        bodyFatCategory(bf)
                    }
                    let recentBodyFat = hk.weeklyBodyFat.filter {
                        $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
                    }
                    if recentBodyFat.count >= 2 {
                        measurementChart(data: recentBodyFat, color: .teal, unit: "%", padding: 0.5)
                    } else if hk.weeklyBodyFat.count >= 2 {
                        measurementChart(data: hk.weeklyBodyFat, color: .teal, unit: "%", padding: 0.5)
                    }
                }
                .padding(.vertical, 4)
            }

            // --- Waist ---
            if let waist = hk.waistCircumferenceCm {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "ruler").foregroundStyle(.purple)
                        Text(String(format: "%.0f cm", waist))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("waist").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if hk.weeklyWaistCm.count >= 2 {
                        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
                        let recentWaist = hk.weeklyWaistCm.filter { $0.date >= cutoff }
                        measurementChart(
                            data: recentWaist.count >= 2 ? recentWaist : hk.weeklyWaistCm,
                            color: .purple, unit: "cm", padding: 1
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            if hasAny {
                Text("Weight, body fat, and waist from Apple Health. Log custom measurements below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("Body Composition", systemImage: "scalemass")
        }
    }

    // MARK: Measurements

    @ViewBuilder
    private var measurementsSection: some View {
        Section {
            if let latest = store.latestBodyMeasurement {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            measurementPill("Waist",  value: latest.waistCm,        unit: "cm", color: .purple)
                            measurementPill("Chest",  value: latest.chestCm,        unit: "cm", color: .blue)
                            measurementPill("Hips",   value: latest.hipsCm,         unit: "cm", color: .pink)
                            measurementPill("Thighs", value: latest.thighsCm,       unit: "cm", color: .teal)
                            measurementPill("Arms",   value: latest.armsCm,         unit: "cm", color: .orange)
                            measurementPill("Neck",   value: latest.neckCm,         unit: "cm", color: .indigo)
                            measurementPill("BF%",    value: latest.bodyFatPercent, unit: "%",  color: .red)
                        }
                    }
                }
                Text("Last logged \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { MeasurementsView() } label: {
                Label("Log Measurements", systemImage: "ruler")
            }
        } header: {
            Label("Measurements", systemImage: "figure.arms.open")
        } footer: {
            Text("Track waist, chest, hips, thighs, arms, neck, and body fat over time.")
        }
    }

    @ViewBuilder
    private func measurementPill(_ label: String, value: Double?, unit: String, color: Color) -> some View {
        if let v = value {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(unit == "%" ? String(format: "%.1f%%", v)
                                 : String(format: "%.0f cm", v))
                    .font(.caption.weight(.semibold)).foregroundStyle(color)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func measurementChart(data: [HealthKitManager.DayMeasurement], color: Color, unit: String, padding: Double) -> some View {
        let minV = (data.map(\.value).min() ?? 0) - padding
        let maxV = (data.map(\.value).max() ?? 100) + padding
        return VStack(alignment: .leading, spacing: 4) {
            Chart(data) { point in
                PointMark(x: .value("Date", point.date, unit: .day), y: .value(unit, point.value))
                    .foregroundStyle(color).symbolSize(50)
                LineMark(x: .value("Date", point.date, unit: .day), y: .value(unit, point.value))
                    .foregroundStyle(color.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYScale(domain: minV...maxV)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 100)
        }
    }

    private func bodyFatCategory(_ pct: Double) -> some View {
        let (label, color): (String, Color) = {
            switch pct {
            case ..<10: return ("Essential", .orange)
            case 10..<20: return ("Athletic", .green)
            case 20..<25: return ("Fitness", .yellow)
            case 25..<30: return ("Average", .orange)
            default: return ("Obese", .red)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Sleep Detail View

struct SleepDetailView: View {
    @Environment(HealthKitManager.self) private var hk

    private struct SleepStagePoint: Identifiable {
        let id = UUID()
        let date: Date
        let stage: String
        let hours: Double
    }

    private var weeklyHasStages: Bool {
        hk.weeklySleep.contains { $0.hasStages }
    }

    private var weeklyStageData: [SleepStagePoint] {
        hk.weeklySleep.flatMap { night -> [SleepStagePoint] in
            guard night.hasStages else {
                return [SleepStagePoint(date: night.date, stage: "Other", hours: night.asleepHours)]
            }
            var pts: [SleepStagePoint] = []
            if night.coreHours > 0 { pts.append(.init(date: night.date, stage: "Core", hours: night.coreHours)) }
            if night.deepHours > 0 { pts.append(.init(date: night.date, stage: "Deep", hours: night.deepHours)) }
            if night.remHours  > 0 { pts.append(.init(date: night.date, stage: "REM",  hours: night.remHours)) }
            let accounted = night.coreHours + night.deepHours + night.remHours
            if night.asleepHours > accounted + 0.05 {
                pts.append(.init(date: night.date, stage: "Other", hours: night.asleepHours - accounted))
            }
            return pts
        }
    }

    var body: some View {
        List {
            if let sleep = hk.lastNightSleep {
                Section("Last Night") {
                    VStack(alignment: .leading, spacing: 14) {

                        // Total + quality
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", sleep.asleepHours))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("hrs asleep").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(sleep.quality)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(qualityColor(sleep.quality))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(qualityColor(sleep.quality).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        // Bedtime → Wake time
                        if let wake = sleep.wakeTime {
                            HStack(spacing: 6) {
                                Image(systemName: "moon.zzz").foregroundStyle(.indigo)
                                Text(sleep.date, style: .time)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Image(systemName: "sunrise").foregroundStyle(.orange)
                                Text(wake, style: .time)
                            }
                            .font(.subheadline)
                        }

                        // In Bed / Asleep / Efficiency
                        HStack(spacing: 20) {
                            statPill(label: "In Bed",  value: String(format: "%.1fh", sleep.inBedHours))
                            statPill(label: "Asleep",  value: String(format: "%.1fh", sleep.asleepHours))
                            if sleep.inBedDuration > 0 {
                                statPill(label: "Efficiency",
                                         value: "\(Int(sleep.asleepDuration / sleep.inBedDuration * 100))%")
                            }
                        }

                        // Stage proportion bar + breakdown
                        if sleep.hasStages {
                            stageBar(sleep)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle").foregroundStyle(.secondary)
                                Text("No stage data — Apple Watch or compatible tracker required.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !hk.weeklySleep.isEmpty {
                let avg = hk.weeklySleep.map(\.asleepHours).reduce(0, +) / Double(max(1, hk.weeklySleep.count))
                Section("Last 7 Nights  ·  avg \(String(format: "%.1f", avg))h") {
                    VStack(alignment: .leading, spacing: 8) {
                        if weeklyHasStages {
                            Chart(weeklyStageData) { pt in
                                BarMark(
                                    x: .value("Night", pt.date, unit: .day),
                                    y: .value("Hours", pt.hours)
                                )
                                .foregroundStyle(by: .value("Stage", pt.stage))
                                .cornerRadius(3)
                            }
                            .chartForegroundStyleScale([
                                "Core":  Color.blue,
                                "Deep":  Color.indigo,
                                "REM":   Color.purple,
                                "Other": Color(.systemFill)
                            ])
                            .chartLegend(position: .bottom, alignment: .leading)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                                }
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(height: 160)
                        } else {
                            Chart(hk.weeklySleep) { night in
                                BarMark(
                                    x: .value("Night", night.date, unit: .day),
                                    y: .value("Hours", night.asleepHours)
                                )
                                .foregroundStyle(qualityColor(night.quality))
                                .cornerRadius(4)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                                }
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(height: 140)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Weekly stage averages
                if weeklyHasStages {
                    let nights = hk.weeklySleep.filter { $0.hasStages }
                    let n = Double(max(1, nights.count))
                    let avgCore = nights.map(\.coreHours).reduce(0, +) / n
                    let avgDeep = nights.map(\.deepHours).reduce(0, +) / n
                    let avgRem  = nights.map(\.remHours).reduce(0, +)  / n
                    Section("Weekly Stage Averages") {
                        HStack(spacing: 0) {
                            stageAvgPill(label: "Core", hours: avgCore, pct: avgCore / (avgCore + avgDeep + avgRem), color: .blue)
                            Divider().frame(height: 40)
                            stageAvgPill(label: "Deep", hours: avgDeep, pct: avgDeep / (avgCore + avgDeep + avgRem), color: .indigo)
                            Divider().frame(height: 40)
                            stageAvgPill(label: "REM",  hours: avgRem,  pct: avgRem  / (avgCore + avgDeep + avgRem), color: .purple)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Section("What Each Stage Does") {
                tipRow(icon: "moon.fill", color: .blue, title: "Core (Light) Sleep",
                       body: "Consolidates memory and transitions between deeper stages. Makes up the largest portion of sleep.")
                tipRow(icon: "moon.fill", color: .indigo, title: "Deep Sleep",
                       body: "Physical restoration, immune function, and growth hormone release. Most restorative stage.")
                tipRow(icon: "moon.fill", color: .purple, title: "REM Sleep",
                       body: "Emotional regulation, learning, and creativity. Dreams occur here. Increases later in the night.")
                tipRow(icon: "clock.fill", color: .secondary, title: "Consistent Schedule",
                       body: "Same bed and wake time every day — including weekends — is the most powerful sleep habit.")
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func stageBar(_ sleep: HealthKitManager.SleepSummary) -> some View {
        let total = sleep.asleepDuration
        if total > 0 {
            let accounted = sleep.coreDuration + sleep.deepDuration + sleep.remDuration
            let other = max(0, total - accounted)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep Stages").font(.caption).foregroundStyle(.secondary)

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if sleep.coreDuration > 0 {
                            Color.blue
                                .frame(width: geo.size.width * CGFloat(sleep.coreDuration / total))
                        }
                        if sleep.deepDuration > 0 {
                            Color.indigo
                                .frame(width: geo.size.width * CGFloat(sleep.deepDuration / total))
                        }
                        if sleep.remDuration > 0 {
                            Color.purple
                                .frame(width: geo.size.width * CGFloat(sleep.remDuration / total))
                        }
                        if other > 0 {
                            Color(.systemFill)
                                .frame(width: geo.size.width * CGFloat(other / total))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 18)

                HStack(spacing: 16) {
                    if sleep.coreDuration > 0 {
                        stageLegend(color: .blue,   label: "Core", hours: sleep.coreHours, total: total)
                    }
                    if sleep.deepDuration > 0 {
                        stageLegend(color: .indigo, label: "Deep", hours: sleep.deepHours, total: total)
                    }
                    if sleep.remDuration > 0 {
                        stageLegend(color: .purple, label: "REM",  hours: sleep.remHours,  total: total)
                    }
                }
            }
        }
    }

    private func stageLegend(color: Color, label: String, hours: Double, total: TimeInterval) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.1fh · %d%%", hours, Int(hours * 3600 / total * 100)))
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func stageAvgPill(label: String, hours: Double, pct: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.1fh", hours)).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(String(format: "%d%%", Int(pct * 100))).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tipRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Good": return .green
        case "OK":   return .yellow
        case "Fair": return .orange
        default:     return .red
        }
    }
}

// MARK: - Compact health summary card (used in TrainView)

struct HealthSummaryCard: View {
    @Environment(HealthKitManager.self) private var hk
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                healthChip(
                    icon: "figure.walk",
                    value: hk.authorizationStatus == .authorized
                        ? Int(hk.todaySteps).formatted() : "—",
                    label: "steps",
                    color: stepsColor
                )
                Divider().frame(height: 32)
                healthChip(
                    icon: "moon.fill",
                    value: hk.authorizationStatus == .authorized
                        ? (hk.lastNightSleep.map { String(format: "%.1fh", $0.asleepHours) } ?? "—") : "—",
                    label: "sleep",
                    color: .indigo
                )
                Divider().frame(height: 32)
                healthChip(
                    icon: "flame.fill",
                    value: hk.authorizationStatus == .authorized
                        ? "\(Int(hk.activeEnergyToday))" : "—",
                    label: "kcal",
                    color: .orange
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var stepsColor: Color {
        guard hk.authorizationStatus == .authorized else { return .accentColor }
        return hk.todaySteps >= 8000 ? .green : .accentColor
    }

    private func healthChip(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
