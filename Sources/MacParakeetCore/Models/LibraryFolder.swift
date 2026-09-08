import Foundation
import GRDB

/// User-created organization metadata inside the transcription Library.
/// This does not represent a directory on disk.
public struct LibraryFolder: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var parentID: UUID?
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension LibraryFolder: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "library_folders"

    public enum Columns: String, ColumnExpression {
        case id, parentID, name, createdAt, updatedAt
    }
}
