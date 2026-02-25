import Foundation

extension FileManager {
    /// Returns the app's `~/Library/Application Support/HomeKitMCP/` directory,
    /// creating it with 0o700 permissions if it doesn't exist.
    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("HomeKitMCP")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appDir.path)
        return appDir
    }
}
