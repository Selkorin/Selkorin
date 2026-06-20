import Foundation

struct UpdateInfo: Codable, Identifiable {
    var id: String { version + "-" + build }
    let version: String
    let build: String
    let channel: String
    let releaseNotes: String
    let downloadURL: String
    let minOSVersion: String?

    // Returns positive if `a` is newer than `b`
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        let len = max(ap.count, bp.count)
        for i in 0..<len {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av > bv ? 1 : -1 }
        }
        return 0
    }

    func isNewerThan(_ current: String) -> Bool {
        UpdateInfo.compareVersions(version, current) > 0
    }
}
