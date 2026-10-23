import Foundation

public enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case gemini
    case chatgpt
    case claude
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .gemini: return "Antigravity"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }
    
    public var fullName: String {
        switch self {
        case .gemini: return "Antigravity (Google)"
        case .chatgpt: return "ChatGPT (OpenAI)"
        case .claude: return "Claude (Anthropic)"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .gemini: return "Google"
        case .chatgpt: return "OpenAI"
        case .claude: return "Anthropic"
        }
    }
}
