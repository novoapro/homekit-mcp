import Foundation

struct AIInteractionLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let provider: String
    let model: String
    let operation: String
    let systemPrompt: String
    let userMessage: String
    let rawResponse: String?
    let parsedSuccessfully: Bool
    let errorMessage: String?
    let durationSeconds: Double
}
