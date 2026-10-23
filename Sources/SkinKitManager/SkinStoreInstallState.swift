import Foundation

/// Where one catalog entry is in the download → install pipeline.
public enum SkinStoreInstallState: Sendable, Equatable {
    case idle
    /// `progress` is 0...1; it stays 0 when the server sends no length.
    case downloading(progress: Double)
    case installing
    case installed
    case failed(message: String)

    /// True while a download or install is running.
    public var isBusy: Bool {
        switch self {
        case .downloading, .installing: return true
        case .idle, .installed, .failed: return false
        }
    }
}
