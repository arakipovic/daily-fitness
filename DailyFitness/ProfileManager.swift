import Foundation

// MARK: - Profile model

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
}

// MARK: - Profile manager

/// Manages multiple user profiles, each with its own isolated Logbook.
/// The default profile (id == ProfileManager.defaultProfileID) reuses
/// LogbookRepository.shared so existing data is preserved without migration.
@MainActor
@Observable
final class ProfileManager {

    static let shared = ProfileManager()

    /// Fixed UUID for the first/default profile — maps to the legacy logbook storage
    /// location. Must never change; changing it would orphan existing user data.
    static let defaultProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private(set) var profiles: [UserProfile]
    private(set) var activeProfileID: UUID

    var activeProfile: UserProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var activeStore: Store {
        store(for: activeProfileID)
    }

    private var storeCache: [UUID: Store] = [:]

    // MARK: - Profile actions

    func addProfile(name: String) -> UserProfile {
        let profile = UserProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Profile" : name,
            createdAt: Date()
        )
        profiles.append(profile)
        saveState()
        return profile
    }

    func switchTo(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeProfileID else { return }
        activeStore.saveImmediately()
        activeProfileID = id
        saveState()
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        storeCache.removeValue(forKey: id)
        if activeProfileID == id {
            activeProfileID = profiles[0].id
        }
        saveState()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveState()
    }

    // MARK: - Store access

    private func store(for id: UUID) -> Store {
        if id == ProfileManager.defaultProfileID {
            return Store.shared
        }
        if let cached = storeCache[id] { return cached }
        let s = Store.makeForProfile(profileID: id)
        storeCache[id] = s
        return s
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    private func saveState() {
        let state = ProfilesState(profiles: profiles, activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL)
        }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let state = try? JSONDecoder().decode(ProfilesState.self, from: data),
           !state.profiles.isEmpty {
            profiles = state.profiles
            activeProfileID = state.activeProfileID
        } else {
            let defaultProfile = UserProfile(
                id: ProfileManager.defaultProfileID,
                name: "Me",
                createdAt: Date()
            )
            profiles = [defaultProfile]
            activeProfileID = defaultProfile.id
            let state = ProfilesState(profiles: profiles, activeProfileID: activeProfileID)
            if let data = try? JSONEncoder().encode(state) {
                try? data.write(to: Self.fileURL)
            }
        }
    }
}

private struct ProfilesState: Codable {
    var profiles: [UserProfile]
    var activeProfileID: UUID
}
