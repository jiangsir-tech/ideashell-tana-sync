import AppKit
import Combine
import Foundation

struct AppUpdate: Decodable, Identifiable {
    let version: String
    let build: Int
    let releaseNotes: [String: String]
    let downloadURL: URL

    var id: Int { build }

    func localizedReleaseNotes(languageCode: String) -> String {
        if languageCode == "en" {
            return releaseNotes["en"] ?? releaseNotes["zh-Hans"] ?? ""
        }
        return releaseNotes["zh-Hans"] ?? releaseNotes["en"] ?? ""
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
    case noUsableRelease
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var discoveredUpdate: AppUpdate?
    @Published var presentedUpdate: AppUpdate?

    let currentVersion: String
    let currentBuild: Int

    private static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/1551255004/ideashell-tana-sync/main/update.json"
    )!
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/1551255004/ideashell-tana-sync/releases?per_page=10"
    )!

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "IdeaSyncDisplayVersion") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        let buildString = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        currentBuild = Int(buildString) ?? 0
    }

    func checkForUpdates() {
        guard state != .checking else { return }
        state = .checking

        Task {
            do {
                let update: AppUpdate
                do {
                    update = try await Self.fetchManifest()
                } catch {
                    update = try await Self.fetchLatestGitHubRelease()
                }
                guard update.downloadURL.scheme == "https" else {
                    state = .failed
                    return
                }

                if update.build > currentBuild {
                    discoveredUpdate = update
                    presentedUpdate = update
                    state = .updateAvailable
                } else {
                    discoveredUpdate = nil
                    state = .upToDate
                }
            } catch {
                state = .failed
            }
        }
    }

    func openDownloadPage(_ update: AppUpdate) {
        NSWorkspace.shared.open(update.downloadURL)
    }

    private static func fetchManifest() async throws -> AppUpdate {
        let data = try await fetchData(from: manifestURL)
        return try JSONDecoder().decode(AppUpdate.self, from: data)
    }

    private static func fetchLatestGitHubRelease() async throws -> AppUpdate {
        let data = try await fetchData(from: releasesURL)
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

        for release in releases where !release.draft {
            let version = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            guard let build = betaBuildNumber(from: version) else { continue }
            let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AppUpdate(
                version: version,
                build: build,
                releaseNotes: ["zh-Hans": notes, "en": notes],
                downloadURL: release.htmlURL
            )
        }

        throw UpdateCheckError.noUsableRelease
    }

    private static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("IdeaSync Update Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw UpdateCheckError.invalidResponse
        }
        return data
    }

    private static func betaBuildNumber(from version: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:beta|build)[.-]?(\d+)$"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(version.startIndex..<version.endIndex, in: version)
        guard let match = regex.firstMatch(in: version, range: range),
              let numberRange = Range(match.range(at: 1), in: version)
        else { return nil }
        return Int(version[numberRange])
    }
}
