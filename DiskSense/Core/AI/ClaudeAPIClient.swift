import Foundation

// Deprecated: 멀티 프로바이더로 이전됨.
// AnthropicClient (AIProviderClient)가 이 파일을 대체함.
// 하위 호환 유지: 기존 키 이름 상수만 보관.
enum ClaudeAPIClient {
    static let apiKeyName = AIProvider.anthropic.keychainKey
}
