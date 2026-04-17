import Foundation
import HomeKit

/// Produces human-readable sentences for automation block logs.
/// These strings are surfaced in the execution log UI (both Swift and web).
enum BlockHumanizer {

    /// Characteristic types that read as an On/Off switch — phrase as "Turn on X" / "Turn off X".
    private static let onOffPowerStates: Set<String> = [
        HMCharacteristicTypePowerState,
        HMCharacteristicTypeActive,
        HMCharacteristicTypeOutletInUse,
    ]

    /// Characteristic types that read as detected/not — phrase as "X detected on Y" / "X cleared on Y".
    private static let detectionStates: Set<String> = [
        HMCharacteristicTypeMotionDetected,
        HMCharacteristicTypeOccupancyDetected,
        HMCharacteristicTypeSmokeDetected,
        HMCharacteristicTypeCarbonMonoxideDetected,
    ]

    private static func truthy(_ value: Any) -> Bool? {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        return nil
    }

    /// Returns a sentence describing a characteristic assignment.
    ///
    /// Examples:
    /// - On-state bool=true → "Turn on Living Room Lamp"
    /// - On-state bool=false → "Turn off Living Room Lamp"
    /// - Brightness=50 → "Set Living Room Lamp Brightness to 50%"
    /// - TargetTemperature=22 → "Set Thermostat Target Temperature to 22°C"
    /// - Lock target=1 → "Lock Front Door"
    static func describeControlDeviceChange(
        deviceName: String,
        characteristicType: String,
        value: Any
    ) -> String {
        // Power / active on-off verbs
        if onOffPowerStates.contains(characteristicType), let on = truthy(value) {
            return on ? "Turn on \(deviceName)" : "Turn off \(deviceName)"
        }

        // Lock mechanism — target state 0 = unsecured, 1 = secured
        if characteristicType == HMCharacteristicTypeTargetLockMechanismState,
           let intVal = (value as? Int) ?? (value as? Double).map(Int.init) {
            return intVal == 0 ? "Unlock \(deviceName)" : "Lock \(deviceName)"
        }

        // Target door state — 0 = open, 1 = closed
        if characteristicType == HMCharacteristicTypeTargetDoorState,
           let intVal = (value as? Int) ?? (value as? Double).map(Int.init) {
            return intVal == 0 ? "Open \(deviceName)" : "Close \(deviceName)"
        }

        // Default: "Set {device} {characteristic} to {formatted value}"
        let formatted = CharacteristicTypes.formatValue(value, characteristicType: characteristicType)
        let charName = CharacteristicTypes.displayName(for: characteristicType)
        return "Set \(deviceName) \(charName) to \(formatted)"
    }

    /// Returns a human-readable duration string.
    /// - `45` → "45s"
    /// - `90` → "1m 30s"
    /// - `120` → "2m"
    /// - `3660` → "1h 1m"
    /// - `0.5` → "0.5s"
    static func formatDurationLong(_ seconds: Double) -> String {
        if seconds < 60 {
            if seconds.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(seconds))s"
            }
            return String(format: "%.1fs", seconds)
        }
        let totalSec = Int(seconds)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let secs = totalSec % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
    }

    /// Returns a short description of what a controlDevice change reverts TO.
    /// Used in timedControl nested-result detail lines.
    static func describeRevertTarget(characteristicType: String, originalValue: Any) -> String {
        CharacteristicTypes.formatValue(originalValue, characteristicType: characteristicType)
    }
}
