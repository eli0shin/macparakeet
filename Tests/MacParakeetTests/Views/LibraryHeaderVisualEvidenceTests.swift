import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class LibraryHeaderVisualEvidenceTests: XCTestCase {
    func testRenderEvidence() async throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["LIBRARY_HEADER_EVIDENCE_DIR"] else {
            throw XCTSkip("Set LIBRARY_HEADER_EVIDENCE_DIR to render Library header evidence.")
        }

        let manager = try DatabaseManager()
        let transcriptionRepository = TranscriptionRepository(dbQueue: manager.dbQueue)
        let folderRepository = LibraryFolderRepository(dbQueue: manager.dbQueue)
        let folder = try folderRepository.create(name: "Project Aurora", parentID: nil)
        let nestedRecordings = [
            Transcription(
                fileName: "Weekly product review.m4a",
                durationMs: 1_842_000,
                status: .completed,
                sourceType: .meeting
            ),
            Transcription(
                fileName: "Aurora research notes.mp3",
                durationMs: 1_135_000,
                status: .completed,
                sourceType: .file
            ),
        ]
        for recording in nestedRecordings {
            try transcriptionRepository.save(recording)
        }
        try transcriptionRepository.moveToLibraryFolder(
            ids: nestedRecordings.map(\.id),
            folderID: folder.id
        )
        try transcriptionRepository.save(
            Transcription(
                fileName: "Research interview.mp3",
                durationMs: 2_415_000,
                status: .completed,
                sourceType: .file
            )
        )

        let viewModel = TranscriptionLibraryViewModel()
        viewModel.configure(
            transcriptionRepo: transcriptionRepository,
            folderRepo: folderRepository
        )
        await viewModel.loadFolders().value
        await viewModel.loadTranscriptions().value

        try render(viewModel: viewModel, name: "root", outputDirectory: outputDirectory)

        viewModel.selectLocation(.folder(folder.id))
        await viewModel.loadTranscriptions().value
        XCTAssertEqual(viewModel.filteredTranscriptions.count, 2)
        try render(viewModel: viewModel, name: "nested-folder", outputDirectory: outputDirectory)

        let selectedRecording = try XCTUnwrap(viewModel.filteredTranscriptions.first)
        viewModel.beginBulkSelection(startingWith: selectedRecording)
        XCTAssertEqual(viewModel.selectedTranscriptionCount, 1)
        try render(viewModel: viewModel, name: "selection", outputDirectory: outputDirectory)
    }

    private func render(
        viewModel: TranscriptionLibraryViewModel,
        name: String,
        outputDirectory: String
    ) throws {
        let size = NSSize(width: 1_000, height: 700)
        let view = TranscriptionLibraryView(
            viewModel: viewModel,
            title: "Library",
            primaryActionTitle: "New Transcription",
            onPrimaryAction: {},
            onSelect: { _ in }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .windowBackgroundColor
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not allocate screenshot bitmap")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode screenshot")
            return
        }

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
