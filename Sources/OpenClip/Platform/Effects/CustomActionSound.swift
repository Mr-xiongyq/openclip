// CustomActionSound.swift
// OpenClip
//
// The user's own file for the action sound. The chosen file is copied into ~/.openclip/sounds, so the sound keeps
// working after the original is moved or deleted. Any format Core Audio decodes is accepted (WAV, AIFF, CAF, MP3,
// M4A/AAC, FLAC); the file must load as a sound, so formats such as OGG and Opus are rejected with a clear message.
import AppKit

public enum CustomActionSound {
    public enum ImportError: Error, Equatable {
        case unreadable
        case tooLong
        case tooLarge
    }

    /// An action sound is a short cue; longer files would cut across the next action.
    static let maxDuration: TimeInterval = 5
    static let maxBytes = 5_000_000

    static let defaultDirectory = URL(fileURLWithPath: ("~/.openclip/sounds" as NSString).expandingTildeInPath, isDirectory: true)

    private static let storedBaseName = "custom"

    /// The imported copy, if any. The extension is kept because Core Audio sniffs the container from it.
    static func storedURL(in directory: URL = defaultDirectory) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == storedBaseName }
    }

    /// Validates `source` and replaces the previous custom sound with a copy of it. Returns the display name.
    @MainActor
    @discardableResult
    static func importFile(from source: URL, into directory: URL = defaultDirectory) throws -> String {
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else { throw ImportError.tooLarge }
        guard let probe = NSSound(contentsOf: source, byReference: true), probe.duration > 0 else { throw ImportError.unreadable }
        guard probe.duration <= maxDuration else { throw ImportError.tooLong }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        remove(from: directory)
        let ext = source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(ext.isEmpty ? storedBaseName : "\(storedBaseName).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return source.deletingPathExtension().lastPathComponent
    }

    static func remove(from directory: URL = defaultDirectory) {
        while let url = storedURL(in: directory) {
            guard (try? FileManager.default.removeItem(at: url)) != nil else { return }
        }
    }
}

extension CustomActionSound.ImportError {
    var message: String {
        switch self {
        case .unreadable: return String(localized: "This file can't be played. Use WAV, AIFF, CAF, MP3, M4A, AAC or FLAC.")
        case .tooLong: return String(localized: "This sound is longer than 5 seconds. Choose a shorter one.")
        case .tooLarge: return String(localized: "This file is larger than 5 MB. Choose a smaller one.")
        }
    }
}
