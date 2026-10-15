import Foundation
import Security

// MARK: - Persistence protocol

protocol LogbookPersisting {
    func load() -> Logbook?
    func save(_ logbook: Logbook)
}

// MARK: - JSON file implementation

struct FileLogbookRepository: LogbookPersisting {
    let fileURL: URL

    func load() -> Logbook? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Logbook.self, from: data)
    }

    func save(_ logbook: Logbook) {
        guard let data = try? JSONEncoder().encode(logbook) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}

// MARK: - File cache + Keychain implementation

struct LogbookRepository: LogbookPersisting {

    // MARK: Factories

    /// Shared repository using the original installation-ID keyed location.
    /// Used by the default profile to preserve existing user data without migration.
    static let shared: LogbookRepository = {
        let dir = appSupportDir()
        let account = logbookKeychainAccount(forInstallationID: installationID())
        return LogbookRepository(
            fileURL: dir.appendingPathComponent("logbook.json"),
            keychainAccount: account
        )
    }()

    /// Creates an isolated repository for additional profiles.
    static func forProfile(_ profileID: UUID) -> LogbookRepository {
        let dir = appSupportDir()
        return LogbookRepository(
            fileURL: dir.appendingPathComponent("logbook-\(profileID.uuidString).json"),
            keychainAccount: "dailyfitness.logbook.v3.\(profileID.uuidString)"
        )
    }

    // MARK: Instance

    private let fileURL: URL
    private let keychainAccount: String

    private init(fileURL: URL, keychainAccount: String) {
        self.fileURL = fileURL
        self.keychainAccount = keychainAccount
    }

    // MARK: LogbookPersisting

    func load() -> Logbook? {
        let fileRepository = FileLogbookRepository(fileURL: fileURL)

        // Fast file cache (written on every save)
        if let lb = fileRepository.load() {
            if let data = try? JSONEncoder().encode(lb) {
                Self.keychainSave(data, account: keychainAccount)
            }
            Self.keychainDeleteLegacyGlobalLogbook()
            return lb
        }

        // Device-local Keychain survives same-device reinstalls, but does not
        // migrate to a different phone or user backup.
        if let data = Self.keychainLoad(account: keychainAccount),
           let lb = try? JSONDecoder().decode(Logbook.self, from: data) {
            fileRepository.save(lb)
            Self.keychainDeleteLegacyGlobalLogbook()
            return lb
        }
        return nil
    }

    func save(_ logbook: Logbook) {
        guard let data = try? JSONEncoder().encode(logbook) else { return }
        FileLogbookRepository(fileURL: fileURL).save(logbook)
        Self.keychainSave(data, account: keychainAccount)
        Self.keychainDeleteLegacyGlobalLogbook()
    }

    // MARK: Public keychain helpers

    static func logbookKeychainAccount(forInstallationID installationID: String) -> String {
        "\(logbookAccountPrefix)\(installationID)"
    }

    // MARK: Private static helpers

    private static let keychainService = "DailyFitness"
    private static let installationIDAccount = "dailyfitness.installationID.v1"
    private static let logbookAccountPrefix = "dailyfitness.logbook.v2."
    private static let legacyGlobalLogbookAccount = "dailyfitness.logbook"

    private static func appSupportDir() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func installationID() -> String {
        if let data = keychainLoad(account: installationIDAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        keychainSave(Data(value.utf8), account: installationIDAccount)
        return value
    }

    private static func keychainSave(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func keychainLoad(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainDeleteLegacyGlobalLogbook() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: legacyGlobalLogbookAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
