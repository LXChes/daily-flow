import Foundation
import OSLog

/// Finds the folder the app and its widgets can both read: an App Group container.
///
/// Why this is careful: the build *asks* for the App Group `requestedGroup`, but a free Apple ID can only
/// get it if the sideloading tool registers it, and that tool usually renames it (adding the team id)
/// and lists the real names under `ALTAppGroups` in the installed Info.plist. So the folder is found at
/// runtime, never assumed: try the renamed groups, then the requested one, and keep the first that the
/// system actually hands over and lets us write to. If none works, everything returns nil and the
/// widgets run in basic mode. Nothing here can crash.
public enum SharedContainer {
    /// The App Group the build requests (see the entitlements files and `docs/widgets-shared-folder.md`).
    public static let requestedGroup = "group.com.example.dailyflow"
    /// Info.plist key a sideloading tool writes the real (renamed) group identifiers under.
    public static let sideloadGroupsKey = "ALTAppGroups"

    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "sharing")
    private static let folderName = "DailyFlow"

    /// The shared folder, found once per process. nil means basic mode.
    public static let directory: URL? = locate()

    public static var isAvailable: Bool { directory != nil }

    /// Group identifiers to try, best first, without duplicates. Pure, for tests.
    public static func candidateGroups(from infoDictionaries: [[String: Any]?]) -> [String] {
        var found: [String] = []
        for info in infoDictionaries {
            guard let value = info?[sideloadGroupsKey] else { continue }
            if let list = value as? [String] {
                found.append(contentsOf: list)
            } else if let single = value as? String {
                found.append(single)
            }
        }
        found.append(requestedGroup)

        var seen = Set<String>()
        return found
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("group.") && seen.insert($0).inserted }
    }

    /// This bundle's Info.plist and, inside a widget extension, the containing app's.
    static func infoDictionaries(for bundle: Bundle) -> [[String: Any]?] {
        var result: [[String: Any]?] = [bundle.infoDictionary]
        if bundle.bundleURL.pathExtension == "appex" {
            // DailyFlow.app/PlugIns/DailyFlowWidget.appex -> DailyFlow.app
            let appURL = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            result.append(Bundle(url: appURL)?.infoDictionary)
        }
        return result
    }

    private static func locate() -> URL? {
        let fileManager = FileManager.default
        for group in candidateGroups(from: infoDictionaries(for: .main)) {
            guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                continue
            }
            let folder = container.appendingPathComponent(folderName, isDirectory: true)
            if isWritable(folder, fileManager: fileManager) {
                logger.info("Shared folder in use: \(group, privacy: .public)")
                return folder
            }
        }
        logger.info("No shared folder: widgets run in basic mode")
        return nil
    }

    /// Creates the folder and proves a file can be written there.
    private static func isWritable(_ folder: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let probe = folder.appendingPathComponent(".probe")
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
}
