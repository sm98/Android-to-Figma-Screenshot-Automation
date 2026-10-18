import Foundation

struct PairedDevice: Codable, Identifiable, Equatable {
    var id: String { androidDeviceId }
    let androidDeviceId: String
    let androidDeviceName: String
    let bearerToken: String
    let pairedAt: Date
}
