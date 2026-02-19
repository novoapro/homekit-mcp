import Foundation
import os

/// Centralized loggers for the app, replacing scattered `print()` calls.
/// Uses `os.Logger` for structured logging with categories and levels.
enum AppLogger {
    static let homeKit = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.homekit-mcp", category: "HomeKit")
    static let server = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.homekit-mcp", category: "MCPServer")
    static let config = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.homekit-mcp", category: "Config")
    static let menuBar = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.homekit-mcp", category: "MenuBar")
    static let general = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.homekit-mcp", category: "General")
}
