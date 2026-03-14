import Foundation

extension FileManager {
    /// Returns the app's Application Support directory, creating it if needed.
    /// In sandbox, this resolves to `~/Library/Containers/<bundle-id>/Data/Library/Application Support/CompAI-Home/`.
    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("CompAI-Home")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appDir.path)
        return appDir
    }
}
