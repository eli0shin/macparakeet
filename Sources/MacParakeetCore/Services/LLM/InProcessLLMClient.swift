import Darwin
import Foundation
import MacParakeetObjCShims
import OSLog

public typealias LocalLLMModelDirectoryResolver = @Sendable (LLMProviderConfig) throws -> URL

public final class InProcessLLMClient: LLMClientProtocol, Sendable {
    public static let modelDirectoryEnvironmentVariable = "MACPARAKEET_LOCAL_LLM_MODEL_DIR"
    public static let defaultIdleUnloadDelaySeconds: TimeInterval = 300
    public static let defaultSmokeTestTimeoutSeconds: TimeInterval = 15

    private let runtime: any LocalLLMRuntime
    private let modelDirectoryResolver: LocalLLMModelDirectoryResolver
    private let idleUnloadDelayNanoseconds: UInt64
    private let smokeTestTimeoutNanoseconds: UInt64
    private let lifetimeCoordinator = LocalLLMLifetimeCoordinator()
    private let logger = Logger(subsystem: "com.macparakeet.core", category: "InProcessLLMClient")

    public init(
        runtime: any LocalLLMRuntime = UnavailableLocalLLMRuntime(),
        modelDirectoryResolver: @escaping LocalLLMModelDirectoryResolver = {
            try InProcessLLMClient.defaultModelDirectory(for: $0)
        },
        idleUnloadDelaySeconds: TimeInterval = InProcessLLMClient.defaultIdleUnloadDelaySeconds,
        smokeTestTimeoutSeconds: TimeInterval = InProcessLLMClient.defaultSmokeTestTimeoutSeconds
    ) {
        self.runtime = runtime
        self.modelDirectoryResolver = modelDirectoryResolver
        let boundedDelay = max(0, idleUnloadDelaySeconds)
        self.idleUnloadDelayNanoseconds = UInt64(boundedDelay * 1_000_000_000)
        let boundedSmokeTestTimeout = max(0, smokeTestTimeoutSeconds)
        self.smokeTestTimeoutNanoseconds = UInt64(boundedSmokeTestTimeout * 1_000_000_000)
    }

    public var supportsInProcessLocalLLM: Bool {
        runtime.isAvailable
    }

    public func chatCompletion(
        messages: [ChatMessage],
        context: LLMExecutionContext,
        options: ChatCompletionOptions
    ) async throws -> ChatCompletionResponse {
        let generation = try await generateResponse(
            messages: messages,
            context: context,
            options: options,
            emit: nil
        )
        return ChatCompletionResponse(
            content: generation.content,
            finishReason: "stop",
            model: context.providerConfig.modelName,
            generationMetrics: generation.metrics
        )
    }

    public func chatCompletionStream(
        messages: [ChatMessage],
        context: LLMExecutionContext,
        options: ChatCompletionOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.generateResponse(
                        messages: messages,
                        context: context,
                        options: options,
                        emit: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func testConnection(context: LLMExecutionContext) async throws {
        guard context.providerConfig.id == .inProcessLocal else {
            throw LLMError.providerError("InProcessLLMClient received \(context.providerConfig.id.rawValue).")
        }

        try await withGenerationLease(delayNanoseconds: 0) {
            try Task.checkCancellation()
            let model = try modelReference(for: context.providerConfig)
            try await runtime.smokeTest(model: model, timeoutNanoseconds: smokeTestTimeoutNanoseconds)
        }
    }

    public func listModels(context: LLMExecutionContext) async throws -> [String] {
        [context.providerConfig.modelName].filter { !$0.isEmpty }
    }

    func hasQueuedGeneration() async -> Bool {
        await lifetimeCoordinator.hasWaitingGeneration
    }

    public func withInProcessLocalModelRemoval(_ operation: @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let lease = try await lifetimeCoordinator.beginGeneration()
        do {
            await runtime.unload()
            try await operation()
            await lifetimeCoordinator.endExclusiveOperation(
                lease,
                waitingGenerationError: Self.modelRemovedDuringRemovalError()
            )
        } catch {
            await lifetimeCoordinator.endExclusiveOperation(
                lease,
                waitingGenerationError: Self.modelRemovalFailedError(error)
            )
            throw error
        }
    }

    private static func modelRemovedDuringRemovalError() -> LLMError {
        .modelNotFound(
            "The downloaded local AI model was removed. Download and verify it again before using local AI."
        )
    }

    private static func modelRemovalFailedError(_ error: Error) -> LLMError {
        .providerError(
            "Local AI model removal did not complete before queued generation could start: \(error.localizedDescription)"
        )
    }

    public static func environmentModelDirectory(for config: LLMProviderConfig) throws -> URL {
        guard let rawPath = ProcessInfo.processInfo.environment[modelDirectoryEnvironmentVariable],
            !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LLMError.modelNotFound(
                "Set \(modelDirectoryEnvironmentVariable) to a local MLX model directory for \(config.modelName)."
            )
        }
        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }

    public static func defaultModelDirectory(for config: LLMProviderConfig) throws -> URL {
        if let rawPath = ProcessInfo.processInfo.environment[modelDirectoryEnvironmentVariable],
            !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: rawPath, isDirectory: true)
        }

        return try managedModelDirectory(for: config)
    }

    static func managedModelDirectory(
        for config: LLMProviderConfig,
        manifest: InProcessLocalModelManifest = InProcessLocalModelCatalog.defaultManifest,
        cacheRoot: URL = InProcessLocalModelCatalog.defaultCacheRoot(),
        fileManager: FileManager = .default
    ) throws -> URL {
        do {
            return try InProcessLocalModelCatalog.verifiedManagedCacheDirectory(
                for: config.modelName,
                manifest: manifest,
                cacheRoot: cacheRoot,
                fileManager: fileManager
            )
        } catch {
            throw LLMError.modelNotFound(
                "Download and verify the local AI model before using \(config.modelName), or set \(modelDirectoryEnvironmentVariable) to a local MLX model directory."
            )
        }
    }

    // MARK: - Generation

    private func generateResponse(
        messages: [ChatMessage],
        context: LLMExecutionContext,
        options: ChatCompletionOptions,
        emit: (@Sendable (String) -> Void)?
    ) async throws -> CollectedLocalLLMResponse {
        guard context.providerConfig.id == .inProcessLocal else {
            throw LLMError.providerError("InProcessLLMClient received \(context.providerConfig.id.rawValue).")
        }

        return try await withGenerationLease(delayNanoseconds: idleUnloadDelayNanoseconds) {
            try Task.checkCancellation()
            try await loadRuntime(for: context.providerConfig)

            let response = try await generateSingle(
                    messages: messages,
                    options: options,
                    emit: emit
                )

            log(metrics: response.metrics, inputCharacters: Self.inputCharacterCount(messages))
            return response
        }
    }

    private func withGenerationLease<T: Sendable>(
        delayNanoseconds: UInt64,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let lease = try await lifetimeCoordinator.beginGeneration()
        do {
            let result = try await operation()
            await lifetimeCoordinator.endGeneration(
                lease,
                runtime: runtime,
                delayNanoseconds: delayNanoseconds
            )
            return result
        } catch {
            await lifetimeCoordinator.endGeneration(
                lease,
                runtime: runtime,
                delayNanoseconds: delayNanoseconds
            )
            throw error
        }
    }

    private func loadRuntime(for config: LLMProviderConfig) async throws {
        try await runtime.load(model: try modelReference(for: config))
    }

    private func modelReference(for config: LLMProviderConfig) throws -> LocalLLMModelReference {
        let directory = try modelDirectoryResolver(config)
        return LocalLLMModelReference(
            modelName: config.modelName,
            directory: directory
        )
    }

    private func generateSingle(
        messages: [ChatMessage],
        options: ChatCompletionOptions,
        emit: (@Sendable (String) -> Void)?
    ) async throws -> CollectedLocalLLMResponse {
        try Task.checkCancellation()
        let rssBefore = ProcessRSSSampler.currentResidentSetSizeBytes()
        let stream = try await runtime.generateStream(messages: messages, options: options)

        var content = ""
        var metrics: LLMGenerationMetrics?
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .text(let text):
                content += text
                emit?(text)
            case .metrics(let eventMetrics):
                metrics = eventMetrics
            }
        }

        let runtimeMetrics: LLMGenerationMetrics?
        if let metrics {
            runtimeMetrics = metrics
        } else {
            runtimeMetrics = await runtime.instrumentation()
        }
        let peakRSS = [rssBefore, ProcessRSSSampler.currentResidentSetSizeBytes(), runtimeMetrics?.peakRSSBytes]
            .compactMap { $0 }
            .max()
        return CollectedLocalLLMResponse(
            content: content,
            metrics: (runtimeMetrics ?? LLMGenerationMetrics()).withPeakRSS(peakRSS)
        )
    }

    private func log(metrics: LLMGenerationMetrics?, inputCharacters: Int) {
        logger.info(
            "Local LLM generation completed inputCharacters=\(inputCharacters, privacy: .public) tokensPerSecond=\(metrics?.tokensPerSecond ?? -1, privacy: .public) promptTokensPerSecond=\(metrics?.promptTokensPerSecond ?? -1, privacy: .public) ttftMs=\(metrics?.timeToFirstTokenMs ?? -1, privacy: .public) peakRSSBytes=\(metrics?.peakRSSBytes ?? 0, privacy: .public)"
        )
    }

    private static func inputCharacterCount(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + $1.modelContent.count }
    }
}

private struct CollectedLocalLLMResponse: Sendable {
    let content: String
    let metrics: LLMGenerationMetrics?
}

private actor LocalLLMLifetimeCoordinator {
    private var unloadTask: Task<Void, Never>?
    private var scheduledUnloadID: UUID?
    private var unloadInProgress = false
    private var activeGenerationID: UUID?
    private var waitingGenerations: [WaitingGeneration] = []

    var hasWaitingGeneration: Bool {
        !waitingGenerations.isEmpty
    }

    func beginGeneration() async throws -> LocalLLMGenerationLease {
        try Task.checkCancellation()
        if unloadInProgress {
            let task = unloadTask
            await task?.value
            return try await beginGeneration()
        }

        if activeGenerationID != nil {
            let lease = LocalLLMGenerationLease(id: UUID())
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (
                        continuation: CheckedContinuation<LocalLLMGenerationLease, Error>
                    ) in
                    waitingGenerations.append(
                        WaitingGeneration(lease: lease, continuation: continuation)
                    )
                }
            } onCancel: {
                Task {
                    await self.cancelWaitingGeneration(id: lease.id)
                }
            }
        }

        let lease = LocalLLMGenerationLease(id: UUID())
        activeGenerationID = lease.id
        cancelPendingUnload()
        return lease
    }

    func endGeneration(
        _ lease: LocalLLMGenerationLease,
        runtime: any LocalLLMRuntime,
        delayNanoseconds: UInt64
    ) {
        guard activeGenerationID == lease.id else { return }

        if !waitingGenerations.isEmpty {
            let next = waitingGenerations.removeFirst()
            activeGenerationID = next.lease.id
            next.continuation.resume(returning: next.lease)
            return
        }

        activeGenerationID = nil
        scheduleUnload(runtime: runtime, delayNanoseconds: delayNanoseconds)
    }

    func endExclusiveOperation(
        _ lease: LocalLLMGenerationLease,
        waitingGenerationError: any Error & Sendable
    ) {
        guard activeGenerationID == lease.id else { return }

        activeGenerationID = nil
        failWaitingGenerations(with: waitingGenerationError)
    }

    private func cancelWaitingGeneration(id: UUID) {
        guard let index = waitingGenerations.firstIndex(where: { $0.lease.id == id }) else { return }

        let waitingGeneration = waitingGenerations.remove(at: index)
        waitingGeneration.continuation.resume(throwing: CancellationError())
    }

    private func failWaitingGenerations(with error: any Error & Sendable) {
        let waiting = waitingGenerations
        waitingGenerations.removeAll()
        waiting.forEach { $0.continuation.resume(throwing: error) }
    }

    private func cancelPendingUnload() {
        unloadTask?.cancel()
        unloadTask = nil
        scheduledUnloadID = nil
    }

    private func scheduleUnload(runtime: any LocalLLMRuntime, delayNanoseconds: UInt64) {
        unloadTask?.cancel()
        let unloadID = UUID()
        scheduledUnloadID = unloadID
        unloadTask = Task {
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                try Task.checkCancellation()
                await self.unloadIfStillScheduled(
                    id: unloadID,
                    runtime: runtime
                )
            } catch {
                return
            }
        }
    }

    private func unloadIfStillScheduled(
        id: UUID,
        runtime: any LocalLLMRuntime
    ) async {
        guard scheduledUnloadID == id,
            activeGenerationID == nil,
            waitingGenerations.isEmpty
        else {
            return
        }

        scheduledUnloadID = nil
        unloadInProgress = true
        await runtime.unload()
        unloadInProgress = false
        unloadTask = nil
    }
}

private struct LocalLLMGenerationLease: Sendable {
    let id: UUID
}

private struct WaitingGeneration {
    let lease: LocalLLMGenerationLease
    let continuation: CheckedContinuation<LocalLLMGenerationLease, Error>
}

private enum ProcessRSSSampler {
    static func currentResidentSetSizeBytes() -> UInt64? {
        #if os(macOS)
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(MPKCurrentTaskPort(), task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
        #else
        return nil
        #endif
    }
}
