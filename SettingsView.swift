import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(GlobalActions.self) private var global
    @Environment(ProfileManager.self) private var profileManager
    @Environment(NotificationManager.self) private var notificationManager
    @State private var showingResetConfirm = false
    @State private var showingProgramPicker = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirm = false
    @State private var backupDocument = LogbookBackupDocument()
    @State private var pendingImport: Logbook?
    @State private var dataAlert: DataManagementAlert?
    @State private var showingAddProfile = false
    @State private var newProfileName = ""
    @State private var showingDeleteProfileConfirm = false
    @State private var profileToDelete: UserProfile?

    var selectedProgram: TrainingProgram? {
        store.catalog.programs.first { $0.id == store.logbook.selectedProgramID }
    }

    private var unit: Unit { store.logbook.unit }

    // Prefer HealthKit weight for accuracy, fall back to profile entry
    private var weightKg: Double {
        healthKit.recentWeightKg ?? store.logbook.profileWeightKg
    }

    var body: some View {
        NavigationStack {
            Form {
                profilesSection

                Section("Program") {
                    LabeledContent("Active Program") {
                        Text(selectedProgram?.name ?? "None")
                            .foregroundStyle(.secondary)
                    }
                    Button("Change Program") {
                        showingProgramPicker = true
                    }
                }

                Section("Units & Preferences") {
                    Picker("Weight Unit", selection: Binding(
                        get: { store.logbook.unit },
                        set: { store.logbook.unit = $0; store.saveLogbook() }
                    )) {
                        ForEach(Unit.allCases) { u in
                            Text(u.rawValue.uppercased()).tag(u)
                        }
                    }

                    Picker("Rest Alerts", selection: Binding(
                        get: { store.logbook.restAlerts },
                        set: { store.logbook.restAlerts = $0; store.saveLogbook() }
                    )) {
                        ForEach(RestAlertSetting.allCases) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                }

                profileBodySection

                if weightKg > 0 {
                    Section {
                        LabeledContent("Protein (fat loss)") {
                            Text("\(Int(weightKg * 1.8))–\(Int(weightKg * 2.2)) g/day")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Protein (maintenance)") {
                            Text("\(Int(weightKg * 1.6))–\(Int(weightKg * 2.0)) g/day")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Safe deficit rate") {
                            let lo = weightKg * 0.005
                            let hi = weightKg * 0.007
                            if unit == .kg {
                                Text("\(String(format: "%.2f", lo))–\(String(format: "%.2f", hi)) kg/week")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(String(format: "%.2f", lo * 2.20462))–\(String(format: "%.2f", hi * 2.20462)) lbs/week")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Based on \(unit.displayWeightString(weightKg, decimals: 0)) \(unit.weightLabel) body weight (1.6–2.2 g protein/kg). Deficit rate = 0.5–0.7% BW/week.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label("Evidence-Based Targets", systemImage: "lightbulb")
                    }
                }

                notificationsSection

                Section("Data") {
                    Button {
                        exportAllData()
                    } label: {
                        Label("Export All Data", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProgramPicker) {
                ProgramPickerSheet()
            }
            .sheet(isPresented: $showingAddProfile) {
                addProfileSheet
            }
            .confirmationDialog(
                "Delete \"\(profileToDelete?.name ?? "")\"?",
                isPresented: $showingDeleteProfileConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Profile", role: .destructive) {
                    if let id = profileToDelete?.id {
                        profileManager.deleteProfile(id)
                    }
                    profileToDelete = nil
                }
                Button("Cancel", role: .cancel) { profileToDelete = nil }
            } message: {
                Text("All workouts, food logs, and settings for this profile will be permanently deleted.")
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    dataAlert = DataManagementAlert(
                        title: "Export Complete",
                        message: "Your DailyFitness backup was exported."
                    )
                case .failure(let error):
                    dataAlert = DataManagementAlert(
                        title: "Export Failed",
                        message: error.localizedDescription
                    )
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .confirmationDialog(
                "Reset all DailyFitness data?",
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset All Data", role: .destructive) {
                    store.resetAllData()
                }
            } message: {
                Text("This deletes workouts, food logs, saved meals, targets, profile details, and settings.")
            }
            .confirmationDialog(
                "Import DailyFitness backup?",
                isPresented: $showingImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace Current Data", role: .destructive) {
                    if let pendingImport {
                        store.replaceLogbook(with: pendingImport)
                        dataAlert = DataManagementAlert(
                            title: "Import Complete",
                            message: "Your DailyFitness data was imported."
                        )
                    }
                    pendingImport = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingImport = nil
                }
            } message: {
                Text(importConfirmationMessage)
            }
            .alert(item: $dataAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Profile body section

    private var profileBodySection: some View {
        Section("Profile") {
            LabeledContent("Name") {
                TextField("Your name", text: Binding(
                    get: { store.logbook.profileName },
                    set: { store.logbook.profileName = $0; store.saveLogbook() }
                ))
                .multilineTextAlignment(.trailing)
            }
            LabeledContent("Age") {
                HStack {
                    Stepper("", value: Binding(
                        get: { store.logbook.profileAge },
                        set: { store.logbook.profileAge = $0; store.saveLogbook() }
                    ), in: 13...99)
                    .labelsHidden()
                    Text("\(store.logbook.profileAge)")
                        .frame(width: 32, alignment: .trailing)
                }
            }
            LabeledContent("Weight (\(unit.weightLabel))") {
                TextField(unit == .kg ? "75" : "165", value: Binding(
                    get: { unit.kgToDisplay(store.logbook.profileWeightKg) },
                    set: { store.logbook.profileWeightKg = unit.displayToKg($0); store.saveLogbook() }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
            if unit == .kg {
                LabeledContent("Height (cm)") {
                    TextField("175", value: Binding(
                        get: { store.logbook.profileHeightCm },
                        set: { store.logbook.profileHeightCm = $0; store.saveLogbook() }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            } else {
                let ftIn = unit.cmToFeetInches(store.logbook.profileHeightCm)
                LabeledContent("Height") {
                    HStack(spacing: 4) {
                        TextField("5", value: Binding(
                            get: { unit.cmToFeetInches(store.logbook.profileHeightCm).feet },
                            set: {
                                let inches = unit.cmToFeetInches(store.logbook.profileHeightCm).inches
                                store.logbook.profileHeightCm = unit.feetInchesToCm(feet: $0, inches: inches)
                                store.saveLogbook()
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                        Text("ft")
                            .foregroundStyle(.secondary)
                        TextField("10", value: Binding(
                            get: { unit.cmToFeetInches(store.logbook.profileHeightCm).inches },
                            set: {
                                let feet = unit.cmToFeetInches(store.logbook.profileHeightCm).feet
                                store.logbook.profileHeightCm = unit.feetInchesToCm(feet: feet, inches: $0)
                                store.saveLogbook()
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                        Text("in")
                            .foregroundStyle(.secondary)
                        let _ = ftIn  // silence unused warning
                    }
                }
            }
            Picker("Sex", selection: Binding(
                get: { store.logbook.profileSex },
                set: { store.logbook.profileSex = $0; store.saveLogbook() }
            )) {
                ForEach(BiologicalSex.allCases) { s in
                    Text(s.rawValue).tag(s as BiologicalSex)
                }
            }
            Picker("Activity Level", selection: Binding(
                get: { store.logbook.profileActivity },
                set: { store.logbook.profileActivity = $0; store.saveLogbook() }
            )) {
                ForEach(ActivityLevel.allCases) { a in
                    Text(a.rawValue).tag(a as ActivityLevel)
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            if notificationManager.permissionStatus == .notDetermined {
                Button {
                    Task { await notificationManager.requestPermission() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
            } else if notificationManager.permissionStatus == .denied {
                Label("Notifications are disabled in System Settings.", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                // Workout reminder
                Toggle("Workout Reminder", isOn: Binding(
                    get: { notificationManager.settings.workoutEnabled },
                    set: { notificationManager.settings.workoutEnabled = $0; notificationManager.saveAndReschedule() }
                ))
                if notificationManager.settings.workoutEnabled {
                    DatePicker("Time", selection: Binding(
                        get: { notifTimeDate(hour: notificationManager.settings.workoutHour,
                                             minute: notificationManager.settings.workoutMinute) },
                        set: { updateNotifTime($0) {
                            notificationManager.settings.workoutHour = $0
                            notificationManager.settings.workoutMinute = $1
                        }}
                    ), displayedComponents: .hourAndMinute)
                }

                // Food log reminder
                Toggle("Food Log Reminder", isOn: Binding(
                    get: { notificationManager.settings.foodEnabled },
                    set: { notificationManager.settings.foodEnabled = $0; notificationManager.saveAndReschedule() }
                ))
                if notificationManager.settings.foodEnabled {
                    DatePicker("Time", selection: Binding(
                        get: { notifTimeDate(hour: notificationManager.settings.foodHour,
                                             minute: notificationManager.settings.foodMinute) },
                        set: { updateNotifTime($0) {
                            notificationManager.settings.foodHour = $0
                            notificationManager.settings.foodMinute = $1
                        }}
                    ), displayedComponents: .hourAndMinute)
                }

                // Measurement reminder
                Toggle("Weekly Measurement Reminder", isOn: Binding(
                    get: { notificationManager.settings.measurementEnabled },
                    set: { notificationManager.settings.measurementEnabled = $0; notificationManager.saveAndReschedule() }
                ))
                if notificationManager.settings.measurementEnabled {
                    Picker("Day", selection: Binding(
                        get: { notificationManager.settings.measurementDayOfWeek },
                        set: { notificationManager.settings.measurementDayOfWeek = $0; notificationManager.saveAndReschedule() }
                    )) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                    DatePicker("Time", selection: Binding(
                        get: { notifTimeDate(hour: notificationManager.settings.measurementHour,
                                             minute: notificationManager.settings.measurementMinute) },
                        set: { updateNotifTime($0) {
                            notificationManager.settings.measurementHour = $0
                            notificationManager.settings.measurementMinute = $1
                        }}
                    ), displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Label("Notifications", systemImage: "bell")
        } footer: {
            Text("Get reminders to work out, log food, and track your body measurements.")
        }
    }

    private func notifTimeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func updateNotifTime(_ date: Date, assign: (Int, Int) -> Void) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        assign(comps.hour ?? 0, comps.minute ?? 0)
        notificationManager.saveAndReschedule()
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        Section {
            ForEach(profileManager.profiles) { profile in
                let isActive = profile.id == profileManager.activeProfileID
                HStack {
                    Image(systemName: isActive ? "person.circle.fill" : "person.circle")
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    Text(profile.name)
                    Spacer()
                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isActive else { return }
                    profileManager.switchTo(profile.id)
                }
                .swipeActions(edge: .trailing) {
                    if profile.id != ProfileManager.defaultProfileID {
                        Button(role: .destructive) {
                            profileToDelete = profile
                            showingDeleteProfileConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            Button {
                showingAddProfile = true
            } label: {
                Label("Add Profile", systemImage: "person.badge.plus")
            }
        } header: {
            Label("Profiles", systemImage: "person.2")
        } footer: {
            Text("Each profile has separate workouts, food logs, and settings. Tap a profile to switch.")
        }
    }

    @ViewBuilder
    private var addProfileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $newProfileName)
                        .onSubmit { commitAddProfile() }
                } footer: {
                    Text("Each profile has completely separate data.")
                }
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddProfile = false
                        newProfileName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitAddProfile() }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func commitAddProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = profileManager.addProfile(name: name)
        profileManager.switchTo(profile.id)
        newProfileName = ""
        showingAddProfile = false
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "dailyfitness-backup-\(formatter.string(from: Date()))"
    }

    private var importConfirmationMessage: String {
        guard let pendingImport else {
            return "This replaces your current workouts, food logs, saved meals, targets, profile details, and settings."
        }
        let workouts = pendingImport.sessions.values.filter { $0.completed != nil }.count
        return "This replaces your current data with \(workouts) workouts, \(pendingImport.foodLog.count) food entries, and \(pendingImport.savedMeals.count) saved meals."
    }

    private func exportAllData() {
        do {
            backupDocument = LogbookBackupDocument(data: try store.exportLogbookData())
            showingExporter = true
        } catch {
            dataAlert = DataManagementAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                pendingImport = try store.decodeLogbookData(data)
                showingImportConfirm = true
            } catch {
                dataAlert = DataManagementAlert(
                    title: "Import Failed",
                    message: "Choose a DailyFitness JSON backup file."
                )
            }
        case .failure(let error):
            dataAlert = DataManagementAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }
}

private struct LogbookBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct DataManagementAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ProgramPickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String = ""
    @State private var startDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    Picker("Program", selection: $selectedID) {
                        ForEach(store.catalog.programs) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }
                Section("Start Date") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                }
                Section {
                    Text("Changing the program will not delete your existing workout logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Change Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !selectedID.isEmpty {
                            store.logbook.selectedProgramID = selectedID
                            store.logbook.startDate = startDate
                            store.saveImmediately()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedID = store.logbook.selectedProgramID
                startDate = store.logbook.startDate
            }
        }
    }
}
