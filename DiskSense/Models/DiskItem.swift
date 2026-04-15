import Foundation

struct DiskItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var path: String
    var name: String
    var sizeBytes: Int64
    var modifiedDate: Date
    var isDirectory: Bool
    var category: StorageCategory
}
