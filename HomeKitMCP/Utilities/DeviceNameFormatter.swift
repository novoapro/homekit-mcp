import Foundation

struct DeviceNameFormatter {
    /// Formats the device name based on the hideRoomName setting.
    /// - Parameters:
    ///   - deviceName: The original name of the device (e.g. "Bedroom Light").
    ///   - roomName: The name of the room the device is in (e.g. "Bedroom").
    ///   - hideRoomName: Whether directly derived room names should be hidden.
    /// - Returns: The formatted name.
    static func format(deviceName: String, roomName: String?, hideRoomName: Bool) -> String {
        guard hideRoomName, let roomName = roomName, !roomName.isEmpty else {
            return deviceName
        }

        // Case-insensitive check
        if deviceName.localizedStandardContains(roomName) {
            // If the device name starts with the room name, strip it
            // We use a range search to handle potential case differences or spacing
            if let range = deviceName.range(of: roomName, options: [.caseInsensitive, .anchored]) {
                var newName = String(deviceName[range.upperBound...])
                // Trim leading whitespace/hyphens that might remain (e.g. " - Light")
                newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if newName.hasPrefix("-") {
                    newName = String(newName.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // If stripping leaves nothing (e.g. device name WAS room name), return original
                return newName.isEmpty ? deviceName : newName
            }
        }
        
        return deviceName
    }
}
