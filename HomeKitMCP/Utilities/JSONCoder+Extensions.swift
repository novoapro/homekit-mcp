import Foundation

// MARK: - Shared JSONEncoder Instances

extension JSONEncoder {
    /// ISO 8601 date encoding, compact output.
    static let iso8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// ISO 8601 date encoding, pretty-printed with sorted keys (for human-readable on-disk storage).
    static let iso8601Pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

// MARK: - Shared JSONDecoder Instances

extension JSONDecoder {
    /// ISO 8601 date decoding.
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
