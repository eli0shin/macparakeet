import GRDB
import XCTest
@testable import MacParakeetCore

final class LibraryFolderRepositoryTests: XCTestCase {
    func testExistingAndNewItemsDefaultToLibraryRoot() throws {
        let manager = try DatabaseManager()
        let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
        let item = Transcription(fileName: "legacy.mp3", status: .completed)

        try transcriptions.save(item)

        XCTAssertNil(try transcriptions.fetch(id: item.id)?.libraryFolderID)
        let root = try transcriptions.fetchLibraryPage(
            query: TranscriptionLibraryQuery(location: .root, limit: 10)
        )
        XCTAssertEqual(root.items.map(\.id), [item.id])
        XCTAssertTrue(DatabaseManager.registeredMigrationIdentifiers.contains("v0.32-library-folders"))
    }

    func testMigrationKeepsExistingItemsAtLibraryRoot() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-folders-migration-\(UUID().uuidString).db").path
        defer { cleanupDatabaseFiles(at: path) }
        let item = Transcription(fileName: "existing.mp3", status: .completed)

        do {
            let current = try DatabaseManager(path: path)
            try TranscriptionRepository(dbQueue: current.dbQueue).save(item)
            try current.dbQueue.write { db in
                try db.execute(sql: "DROP INDEX idx_transcriptions_library_folder_created_at")
                try db.execute(sql: "ALTER TABLE transcriptions DROP COLUMN libraryFolderID")
                try db.execute(sql: "DROP TABLE library_folders")
                try db.execute(
                    sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                    arguments: ["v0.32-library-folders"]
                )
            }
        }

        let migrated = try DatabaseManager(path: path)
        let persisted = try TranscriptionRepository(dbQueue: migrated.dbQueue).fetch(id: item.id)

        XCTAssertNil(persisted?.libraryFolderID)
        XCTAssertEqual(
            try TranscriptionRepository(dbQueue: migrated.dbQueue).fetchLibraryPage(
                query: TranscriptionLibraryQuery(location: .root, limit: 10)
            ).items.map(\.id),
            [item.id]
        )
    }

    func testNestedHierarchyAndMembershipPersistAcrossDatabaseRestart() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-folders-\(UUID().uuidString).db").path
        defer { cleanupDatabaseFiles(at: path) }

        let item = Transcription(fileName: "meeting.m4a", status: .completed, sourceType: .meeting)
        let childID: UUID
        do {
            let manager = try DatabaseManager(path: path)
            let folders = LibraryFolderRepository(dbQueue: manager.dbQueue)
            let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
            let parent = try folders.create(name: "Projects", parentID: nil)
            let child = try folders.create(name: "Sprint", parentID: parent.id)
            childID = child.id
            try transcriptions.save(item)
            try transcriptions.moveToLibraryFolder(ids: [item.id], folderID: child.id)
        }

        let reopened = try DatabaseManager(path: path)
        let folders = try LibraryFolderRepository(dbQueue: reopened.dbQueue).fetchAll()
        let persisted = try TranscriptionRepository(dbQueue: reopened.dbQueue).fetch(id: item.id)

        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(
            folders.first(where: { $0.id == childID })?.parentID, folders.first(where: { $0.name == "Projects" })?.id)
        XCTAssertEqual(persisted?.libraryFolderID, childID)
    }

    func testMoveAllSupportedItemTypesAndMoveBackToRoot() throws {
        let manager = try DatabaseManager()
        let folders = LibraryFolderRepository(dbQueue: manager.dbQueue)
        let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
        let folder = try folders.create(name: "Mixed", parentID: nil)
        let items = Transcription.SourceType.allCases.map {
            Transcription(fileName: "\($0.rawValue).m4a", status: .completed, sourceType: $0)
        }
        for item in items { try transcriptions.save(item) }

        try transcriptions.moveToLibraryFolder(ids: items.map(\.id), folderID: folder.id)

        let folderPage = try transcriptions.fetchLibraryPage(
            query: TranscriptionLibraryQuery(location: .folder(folder.id), limit: 10)
        )
        XCTAssertEqual(Set(folderPage.items.map(\.sourceType)), Set(Transcription.SourceType.allCases))
        XCTAssertTrue(
            try transcriptions.fetchLibraryPage(
                query: TranscriptionLibraryQuery(location: .root, limit: 10)
            ).items.isEmpty)

        try transcriptions.moveToLibraryFolder(ids: items.map(\.id), folderID: nil)
        XCTAssertEqual(
            try transcriptions.fetchLibraryPage(
                query: TranscriptionLibraryQuery(location: .root, limit: 10)
            ).items.count, items.count)
    }

    func testRecursiveFolderDeletionRetainsItemsAtLibraryRoot() throws {
        let manager = try DatabaseManager()
        let folders = LibraryFolderRepository(dbQueue: manager.dbQueue)
        let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
        let parent = try folders.create(name: "Parent", parentID: nil)
        let child = try folders.create(name: "Child", parentID: parent.id)
        let parentItem = Transcription(fileName: "video.m4a", status: .completed, sourceType: .youtube)
        let childItem = Transcription(fileName: "meeting.m4a", status: .completed, sourceType: .meeting)
        try transcriptions.save(parentItem)
        try transcriptions.save(childItem)
        try transcriptions.moveToLibraryFolder(ids: [parentItem.id], folderID: parent.id)
        try transcriptions.moveToLibraryFolder(ids: [childItem.id], folderID: child.id)

        XCTAssertTrue(try folders.delete(id: parent.id))

        XCTAssertTrue(try folders.fetchAll().isEmpty)
        XCTAssertNil(try transcriptions.fetch(id: parentItem.id)?.libraryFolderID)
        XCTAssertNil(try transcriptions.fetch(id: childItem.id)?.libraryFolderID)
        XCTAssertEqual(
            Set(
                try transcriptions.fetchLibraryPage(
                    query: TranscriptionLibraryQuery(location: .root, limit: 10)
                ).items.map(\.id)),
            [parentItem.id, childItem.id]
        )
    }

    func testStaleCompletionSaveCannotUndoMoveOrRestoreDeletedFolder() throws {
        let manager = try DatabaseManager()
        let folders = LibraryFolderRepository(dbQueue: manager.dbQueue)
        let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
        let folder = try folders.create(name: "Active", parentID: nil)
        let item = Transcription(fileName: "processing-meeting.m4a", status: .processing, sourceType: .meeting)
        try transcriptions.save(item)
        var staleRootSnapshot = try XCTUnwrap(transcriptions.fetch(id: item.id))

        try transcriptions.moveToLibraryFolder(ids: [item.id], folderID: folder.id)
        staleRootSnapshot.status = .completed
        try transcriptions.save(staleRootSnapshot)
        let moved = try XCTUnwrap(transcriptions.fetch(id: item.id))
        XCTAssertEqual(moved.libraryFolderID, folder.id)
        XCTAssertEqual(moved.status, .completed)

        let staleFolderSnapshot = moved
        XCTAssertTrue(try folders.delete(id: folder.id))
        XCTAssertNoThrow(try transcriptions.save(staleFolderSnapshot))
        XCTAssertNil(try transcriptions.fetch(id: item.id)?.libraryFolderID)
    }

    func testInvalidDestinationRollsBackWholeMove() throws {
        let manager = try DatabaseManager()
        let transcriptions = TranscriptionRepository(dbQueue: manager.dbQueue)
        let first = Transcription(fileName: "first.m4a", status: .completed)
        let second = Transcription(fileName: "second.m4a", status: .completed)
        try transcriptions.save(first)
        try transcriptions.save(second)

        XCTAssertThrowsError(
            try transcriptions.moveToLibraryFolder(ids: [first.id, second.id], folderID: UUID())
        ) { error in
            XCTAssertEqual(error as? LibraryFolderError, .folderNotFound)
        }
        XCTAssertNil(try transcriptions.fetch(id: first.id)?.libraryFolderID)
        XCTAssertNil(try transcriptions.fetch(id: second.id)?.libraryFolderID)
    }

    func testFolderNamesAreTrimmedAndUniqueWithinOneParent() throws {
        let manager = try DatabaseManager()
        let folders = LibraryFolderRepository(dbQueue: manager.dbQueue)
        let parent = try folders.create(name: "Projects", parentID: nil)
        let created = try folders.create(name: "  Sprint  ", parentID: parent.id)

        XCTAssertEqual(created.name, "Sprint")
        XCTAssertThrowsError(try folders.create(name: "sprint", parentID: parent.id)) { error in
            XCTAssertEqual(error as? LibraryFolderError, .duplicateName)
        }
        XCTAssertNoThrow(try folders.create(name: "Sprint", parentID: nil))
        XCTAssertThrowsError(try folders.create(name: "Nested", parentID: UUID())) { error in
            XCTAssertEqual(error as? LibraryFolderError, .parentNotFound)
        }
    }

    private func cleanupDatabaseFiles(at path: String) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal", ".migration.lock"] {
            try? fileManager.removeItem(atPath: path + suffix)
        }
    }
}
