import Foundation
import GRDB

public enum LibraryFolderError: LocalizedError, Equatable {
    case invalidName
    case parentNotFound
    case duplicateName
    case folderNotFound
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a folder name."
        case .parentNotFound:
            return "The parent folder no longer exists."
        case .duplicateName:
            return "A folder with this name already exists here."
        case .folderNotFound:
            return "The folder no longer exists."
        case .itemNotFound:
            return "A Library item no longer exists."
        }
    }
}

public protocol LibraryFolderRepositoryProtocol: Sendable {
    func fetchAll() throws -> [LibraryFolder]
    func create(name: String, parentID: UUID?) throws -> LibraryFolder
    @discardableResult func delete(id: UUID) throws -> Bool
}

/// Persists the Library folder hierarchy. Item membership remains on the
/// transcription row so the database foreign keys can make recursive folder
/// deletion atomic and return every affected item to Library root.
public final class LibraryFolderRepository: LibraryFolderRepositoryProtocol, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func fetchAll() throws -> [LibraryFolder] {
        try dbQueue.read { db in
            try LibraryFolder
                .order(LibraryFolder.Columns.name.collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
        }
    }

    public func create(name: String, parentID: UUID?) throws -> LibraryFolder {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw LibraryFolderError.invalidName }

        return try dbQueue.write { db in
            if let parentID, try LibraryFolder.fetchOne(db, key: parentID) == nil {
                throw LibraryFolderError.parentNotFound
            }
            let duplicateExists =
                try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1 FROM library_folders
                            WHERE parentID IS ? AND name = ? COLLATE NOCASE
                        )
                        """,
                    arguments: [parentID, normalizedName]
                ) ?? false
            guard !duplicateExists else { throw LibraryFolderError.duplicateName }

            let folder = LibraryFolder(parentID: parentID, name: normalizedName)
            try folder.insert(db)
            return folder
        }
    }

    public func delete(id: UUID) throws -> Bool {
        try dbQueue.write { db in
            guard try LibraryFolder.fetchOne(db, key: id) != nil else {
                throw LibraryFolderError.folderNotFound
            }
            return try LibraryFolder.deleteOne(db, key: id)
        }
    }
}
