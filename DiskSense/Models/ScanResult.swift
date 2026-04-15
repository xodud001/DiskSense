import Foundation

struct ScanResult: Codable {
    var scannedAt: Date
    var totalCapacity: Int64
    var totalUsed: Int64
    var items: [DiskItem]
    var breakdown: [StorageCategory: Int64]
}
