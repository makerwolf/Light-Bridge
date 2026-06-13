import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02X ", $0) }.joined().trimmingCharacters(in: .whitespaces)
    }
}
