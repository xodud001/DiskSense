import Foundation

/// UserDefaults 래퍼. 설정 값 관리.
enum SettingsStore {
    private enum Keys {
        static let autoRescanHours = "autoRescanHours"
        static let deleteMode = "deleteMode"
        static let threshold1 = "threshold1"
        static let threshold2 = "threshold2"
        static let threshold3 = "threshold3"
        static let notificationsEnabled = "notificationsEnabled"
    }

    enum DeleteMode: String, CaseIterable, Identifiable {
        case trash, permanent
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .trash: return "휴지통으로 이동 (안전)"
            case .permanent: return "영구 삭제 (복구 불가)"
            }
        }
    }

    static var autoRescanHours: Double {
        get { UserDefaults.standard.double(forKey: Keys.autoRescanHours).nonZero ?? 12 }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoRescanHours) }
    }

    static var deleteMode: DeleteMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.deleteMode),
                  let mode = DeleteMode(rawValue: raw) else { return .trash }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.deleteMode) }
    }

    static var thresholds: [Double] {
        get {
            let d = UserDefaults.standard
            let t1 = d.double(forKey: Keys.threshold1).nonZero ?? 0.70
            let t2 = d.double(forKey: Keys.threshold2).nonZero ?? 0.85
            let t3 = d.double(forKey: Keys.threshold3).nonZero ?? 0.95
            return [t1, t2, t3]
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue[safe: 0] ?? 0.70, forKey: Keys.threshold1)
            d.set(newValue[safe: 1] ?? 0.85, forKey: Keys.threshold2)
            d.set(newValue[safe: 2] ?? 0.95, forKey: Keys.threshold3)
        }
    }

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.notificationsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    static var selectedModelId: String {
        get {
            UserDefaults.standard.string(forKey: "selectedModelId") ?? ModelRegistry.firstRunDefault().id
        }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModelId") }
    }

    static var selectedModel: AIModel {
        ModelRegistry.find(selectedModelId) ?? ModelRegistry.default
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
