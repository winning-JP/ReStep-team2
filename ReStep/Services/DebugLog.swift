import Foundation

enum DebugLog {
    static func log(_ message: String) {
        #if DEBUG
        print("[ReStep] \(message)")
        #endif
    }
}

