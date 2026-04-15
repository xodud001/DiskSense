import Foundation

extension AIModel {
    var isAvailable: Bool {
        KeychainHelper.has(key: provider.keychainKey)
    }
}

extension AIProvider {
    static var anyConfigured: Bool {
        AIProvider.allCases.contains { KeychainHelper.has(key: $0.keychainKey) }
    }

    var isConfigured: Bool {
        KeychainHelper.has(key: keychainKey)
    }
}
