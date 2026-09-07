import Foundation

public struct AppPromptContext: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String?
    public let category: AppCategory

    public init(
        bundleIdentifier: String?,
        displayName: String? = nil,
        category: AppCategory? = nil
    ) {
        let normalizedBundleID = Self.normalizedBundleIdentifier(bundleIdentifier)
        self.bundleIdentifier = normalizedBundleID
        self.displayName = Self.normalizedDisplayName(displayName)
        self.category = category ?? AppCategory(bundleIdentifier: normalizedBundleID)
    }

    public static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    public static func normalizedDisplayName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    public func isSelfApp(bundleIdentifier appBundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier,
            let appBundleIdentifier = Self.normalizedBundleIdentifier(appBundleIdentifier)
        else {
            return false
        }
        return bundleIdentifier == appBundleIdentifier
    }
}
