import Foundation
import SwiftUI

enum StorageCategory: String, CaseIterable, Codable, Identifiable {
    case apps, documents, photos, developer, system, cache, mail, trash, other
    case macOS, otherUsers, snapshots, systemData
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apps:        return "응용 프로그램"
        case .documents:   return "문서"
        case .photos:      return "미디어 파일"
        case .developer:   return "개발"
        case .system:      return "시스템"
        case .cache:       return "캐시"
        case .mail:        return "메일"
        case .trash:       return "휴지통"
        case .other:       return "기타"
        case .macOS:       return "macOS"
        case .otherUsers:  return "다른 사용자"
        case .snapshots:   return "APFS 스냅샷"
        case .systemData:  return "시스템 데이터"
        }
    }

    var systemImage: String {
        switch self {
        case .apps:        return "app.fill"
        case .documents:   return "doc.fill"
        case .photos:      return "photo.fill"
        case .developer:   return "hammer.fill"
        case .system:      return "gearshape.2.fill"
        case .cache:       return "tray.full.fill"
        case .mail:        return "envelope.fill"
        case .trash:       return "trash.fill"
        case .other:       return "ellipsis.circle.fill"
        case .macOS:       return "macwindow"
        case .otherUsers:  return "person.2.fill"
        case .snapshots:   return "camera.filters"
        case .systemData:  return "cpu"
        }
    }

    var color: Color {
        switch self {
        case .apps:        return .blue
        case .documents:   return .indigo
        case .photos:      return .pink
        case .developer:   return .orange
        case .system:      return .gray
        case .cache:       return .yellow
        case .mail:        return .teal
        case .trash:       return .red
        case .other:       return .secondary
        case .macOS:       return .mint
        case .otherUsers:  return .purple
        case .snapshots:   return .brown
        case .systemData:  return .gray
        }
    }
}

enum RiskLevel: String, Codable {
    case safe, caution, danger
}
