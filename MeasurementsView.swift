import SwiftUI
import Charts

// MARK: - Main view

struct MeasurementsView: View {
    @Environment(Store.self) private var store
    @State private var showingAdd = false

    private var sorted: [BodyMeasurement] {
        store.logbook.bodyMeasurements.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if sorted.count >= 2 {
                trendsSection
            }
            historySection
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddMeasurementView()
        }
    }

    // MARK: Trends

    private var trendsSection: some View {
        let ascending = store.logbook.bodyMeasurements.sorted { $0.date < $1.date }
        return Section("Trends") {
            let waist   = ascending.compactMap { m in m.waistCm.map        { (m.date, $0) } }
            let chest   = ascending.compactMap { m in m.chestCm.map        { (m.date, $0) } }
            let hips    = ascending.compactMap { m in m.hipsCm.map         { (m.date, $0) } }
            let thighs  = ascending.compactMap { m in m.thighsCm.map       { (m.date, $0) } }
            let arms    = ascending.compactMap { m in m.armsCm.map         { (m.date, $0) } }
            let neck    = ascending.compactMap { m in m.neckCm.map         { (m.date, $0) } }
            let bf      = ascending.compactMap { m in m.bodyFatPercent.map { (m.date, $0) } }

            if waist.count  >= 2 { trendLine(waist,  label: "Waist",    unit: "cm", color: .purple) }
            if chest.count  >= 2 { trendLine(chest,  label: "Chest",    unit: "cm", color: .blue)   }
            if hips.count   >= 2 { trendLine(hips,   label: "Hips",     unit: "cm", color: .pink)   }
            if thighs.count >= 2 { trendLine(thighs, label: "Thighs",   unit: "cm", color: .teal)   }
            if arms.count   >= 2 { trendLine(arms,   label: "Arms",     unit: "cm", color: .orange) }
            if neck.count   >= 2 { trendLine(neck,   label: "Neck",     unit: "cm", color: .indigo) }
            if bf.count     >= 2 { trendLine(bf,     label: "Body Fat", unit: "%",  color: .red)    }
        }
    }

    private func trendLine(_ data: [(Date, Double)], label: String, unit: String, color: Color) -> some View {
        let values = data.map(\.1)
        let minV   = (values.min() ?? 0)
        let maxV   = (values.max() ?? 100)
        let pad    = max((maxV - minV) * 0.15, 0.5)
        let recent = values.last ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text(unit == "%" ? String(format: "%.1f%%", recent)
                                 : String(format: "%.1f cm", recent))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }
            Chart {
                ForEach(data.indices, id: \.self) { i in
                    LineMark(x: .value("Date", data[i].0), y: .value(label, data[i].1))
                        .foregroundStyle(color.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Date", data[i].0), y: .value(label, data[i].1))
                        .foregroundStyle(color)
                        .symbolSize(36)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYScale(domain: (minV - pad)...(maxV + pad))
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 90)
        }
        .padding(.vertical, 4)
    }

    // MARK: History

    private var historySection: some View {
        Section("History") {
            if sorted.isEmpty {
                ContentUnavailableView {
                    Label("No Measurements", systemImage: "ruler")
                } description: {
                    Text("Tap + to log your first entry.")
                }
            } else {
                ForEach(sorted) { m in
                    MeasurementHistoryRow(measurement: m)
                }
                .onDelete { offsets in
                    store.deleteBodyMeasurements(at: offsets, from: sorted)
                }
            }
        }
    }
}

// MARK: - History row

struct MeasurementHistoryRow: View {
    let measurement: BodyMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(measurement.date, style: .date)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Waist",    value: measurement.waistCm,        unit: "cm")
                    chip("Chest",    value: measurement.chestCm,        unit: "cm")
                    chip("Hips",     value: measurement.hipsCm,         unit: "cm")
                    chip("Thighs",   value: measurement.thighsCm,       unit: "cm")
                    chip("Arms",     value: measurement.armsCm,         unit: "cm")
                    chip("Neck",     value: measurement.neckCm,         unit: "cm")
                    chip("Body Fat", value: measurement.bodyFatPercent, unit: "%")
                }
            }
            if !measurement.note.isEmpty {
                Text(measurement.note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func chip(_ label: String, value: Double?, unit: String) -> some View {
        if let v = value {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(unit == "%" ? String(format: "%.1f%%", v)
                                 : String(format: "%.1f cm", v))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Add / edit measurement

struct AddMeasurementView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var logDate = Date()
    @State private var waistText = ""
    @State private var chestText = ""
    @State private var hipsText = ""
    @State private var thighsText = ""
    @State private var armsText = ""
    @State private var neckText = ""
    @State private var bodyFatText = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $logDate, displayedComponents: .date)
                }

                Section("Circumferences (cm)") {
                    field("Waist",        text: $waistText)
                    field("Chest",        text: $chestText)
                    field("Hips",         text: $hipsText)
                    field("Thighs",       text: $thighsText)
                    field("Arms (bicep)", text: $armsText)
                    field("Neck",         text: $neckText)
                }

                Section("Body Composition") {
                    field("Body Fat %", text: $bodyFatText, placeholder: "e.g. 15.5")
                }

                if !note.isEmpty || !hasAnyValue {
                    Section("Notes") {
                        TextField("Optional note", text: $note, axis: .vertical)
                            .lineLimit(3)
                    }
                }
            }
            .navigationTitle("Log Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasAnyValue)
                }
            }
            .onAppear { prefillFromExisting() }
            .onChange(of: logDate) { _, _ in prefillFromExisting() }
        }
    }

    private var hasAnyValue: Bool {
        [waistText, chestText, hipsText, thighsText, armsText, neckText, bodyFatText]
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String = "") -> some View {
        LabeledContent(label) {
            TextField(placeholder.isEmpty ? "—" : placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func prefillFromExisting() {
        guard let existing = store.logbook.bodyMeasurements.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: logDate)
        }) else {
            waistText = ""; chestText = ""; hipsText = ""; thighsText = ""
            armsText = ""; neckText = ""; bodyFatText = ""; note = ""
            return
        }
        waistText    = existing.waistCm.map        { String(format: "%.1f", $0) } ?? ""
        chestText    = existing.chestCm.map        { String(format: "%.1f", $0) } ?? ""
        hipsText     = existing.hipsCm.map         { String(format: "%.1f", $0) } ?? ""
        thighsText   = existing.thighsCm.map       { String(format: "%.1f", $0) } ?? ""
        armsText     = existing.armsCm.map         { String(format: "%.1f", $0) } ?? ""
        neckText     = existing.neckCm.map         { String(format: "%.1f", $0) } ?? ""
        bodyFatText  = existing.bodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
        note         = existing.note
    }

    private func save() {
        let m = BodyMeasurement(
            date: logDate,
            waistCm:        Double(waistText.replacingOccurrences(of: ",", with: ".")),
            chestCm:        Double(chestText.replacingOccurrences(of: ",", with: ".")),
            hipsCm:         Double(hipsText.replacingOccurrences(of: ",", with: ".")),
            thighsCm:       Double(thighsText.replacingOccurrences(of: ",", with: ".")),
            armsCm:         Double(armsText.replacingOccurrences(of: ",", with: ".")),
            neckCm:         Double(neckText.replacingOccurrences(of: ",", with: ".")),
            bodyFatPercent: Double(bodyFatText.replacingOccurrences(of: ",", with: ".")),
            note: note
        )
        store.addBodyMeasurement(m)
        dismiss()
    }
}
