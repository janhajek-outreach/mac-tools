import Foundation
import AppKit

/// The kind of content an item holds.
enum ClipItemKind: String, Codable {
    case text
    case image
    case file
}

/// A single clipboard/snippet entry. Text is stored inline; image/file bytes are
/// stored as a blob file on disk and referenced by `blobFilename`.
struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: ClipItemKind
    var label: String?
    var createdAt: Date

    /// For `.text`: the text content. For image/file: nil.
    var text: String?

    /// For `.image` / `.file`: the blob filename under the blobs directory.
    var blobFilename: String?

    /// For `.file`: original file name for display / re-paste.
    var originalName: String?

    init(
        id: UUID = UUID(),
        kind: ClipItemKind,
        label: String? = nil,
        createdAt: Date = Date(),
        text: String? = nil,
        blobFilename: String? = nil,
        originalName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.createdAt = createdAt
        self.text = text
        self.blobFilename = blobFilename
        self.originalName = originalName
    }

    /// True when the item is plain text and therefore editable (F2).
    var isEditableText: Bool { kind == .text }

    /// A one-line title for the row. Prefers the user label.
    var displayTitle: String {
        if let label = label, !label.isEmpty { return label }
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "(empty)" : t
        case .image:
            return "Image"
        case .file:
            return originalName ?? "File"
        }
    }

    /// Used to de-duplicate identical content in the auto-capture tab.
    var dedupKey: String {
        switch kind {
        case .text:  return "text:\(text ?? "")"
        case .image: return "image:\(blobFilename ?? UUID().uuidString)"
        case .file:  return "file:\(originalName ?? "")"
        }
    }
}
