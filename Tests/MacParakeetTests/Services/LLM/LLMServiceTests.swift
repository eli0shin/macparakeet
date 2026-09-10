import XCTest
@testable import MacParakeetCore

// MARK: - Mocks

final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    var supportsInProcessLocalLLM = true
    var capturedMessages: [ChatMessage] = []
    var capturedContext: LLMExecutionContext?
    var capturedOptions: ChatCompletionOptions?
    var responseContent = "Mock response"
    var responseContents: [String] = []
    var chatCompletionCallCount = 0
    var responseReasoningContent: String?
    var responseFinishReason: String?
    var responseModel = "mock-model"
    var responseUsage: TokenUsage?
    var streamTokens: [String]?
    var testConnectionError: Error?
    var testConnectionDelayNs: UInt64 = 0
    var chatCompletionError: Error?
    var holdInProcessModelRemoval = false
    var inProcessModelRemovalCallCount = 0
    private var inProcessModelRemovalContinuation: CheckedContinuation<Void, Never>?

    func chatCompletion(
        messages: [ChatMessage],
        context: LLMExecutionContext,
        options: ChatCompletionOptions
    ) async throws -> ChatCompletionResponse {
        chatCompletionCallCount += 1
        capturedMessages = messages
        capturedContext = context
        capturedOptions = options
        if let chatCompletionError { throw chatCompletionError }
        let content = responseContents.isEmpty ? responseContent : responseContents.removeFirst()
        return ChatCompletionResponse(
            content: content,
            reasoningContent: responseReasoningContent,
            finishReason: responseFinishReason,
            model: responseModel,
            usage: responseUsage
        )
    }

    func chatCompletionStream(
        messages: [ChatMessage],
        context: LLMExecutionContext,
        options: ChatCompletionOptions
    ) -> AsyncThrowingStream<String, Error> {
        capturedMessages = messages
        capturedContext = context
        capturedOptions = options
        if let chatCompletionError {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: chatCompletionError)
            }
        }
        let tokens = streamTokens ?? [responseContent]
        return AsyncThrowingStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func testConnection(context: LLMExecutionContext) async throws {
        capturedContext = context
        if testConnectionDelayNs > 0 {
            try await Task.sleep(nanoseconds: testConnectionDelayNs)
        }
        if let error = testConnectionError { throw error }
    }

    var modelsList: [String] = ["mock-model-1", "mock-model-2"]
    var listModelsError: Error?

    func listModels(context: LLMExecutionContext) async throws -> [String] {
        capturedContext = context
        if let error = listModelsError { throw error }
        return modelsList
    }

    func withInProcessLocalModelRemoval(_ operation: @Sendable () async throws -> Void) async throws {
        inProcessModelRemovalCallCount += 1
        if holdInProcessModelRemoval {
            await withCheckedContinuation { continuation in
                inProcessModelRemovalContinuation = continuation
            }
        }
        try await operation()
    }

    func releaseInProcessModelRemoval() {
        holdInProcessModelRemoval = false
        inProcessModelRemovalContinuation?.resume()
        inProcessModelRemovalContinuation = nil
    }
}

final class MockLLMExecutionContextResolver: LLMExecutionContextResolving, @unchecked Sendable {
    let configStore: MockLLMConfigStore
    var localCLIConfig: LocalCLIConfig?
    var resolveError: Error?

    init(configStore: MockLLMConfigStore, localCLIConfig: LocalCLIConfig? = nil) {
        self.configStore = configStore
        self.localCLIConfig = localCLIConfig
    }

    func resolveContext() throws -> LLMExecutionContext? {
        if let resolveError {
            throw resolveError
        }
        guard let config = try configStore.loadConfig() else { return nil }
        let resolvedLocalCLIConfig = config.id == .localCLI ? localCLIConfig : nil
        return LLMExecutionContext(
            providerConfig: config,
            localCLIConfig: resolvedLocalCLIConfig
        )
    }
}

final class MockLLMConfigStore: LLMConfigStoreProtocol, @unchecked Sendable {
    var config: LLMProviderConfig?
    var loadConfigCallCount = 0
    var loadAPIKeyCallCount = 0
    /// Per-provider key storage for testing provider switching.
    var storedKeys: [LLMProviderID: String] = [:]

    func loadConfig() throws -> LLMProviderConfig? {
        loadConfigCallCount += 1
        return config
    }
    func saveConfig(_ config: LLMProviderConfig) throws {
        self.config = config
        if let key = config.apiKey {
            storedKeys[config.id] = key
        } else {
            storedKeys.removeValue(forKey: config.id)
        }
    }
    func deleteConfig() throws {
        if let id = config?.id {
            storedKeys.removeValue(forKey: id)
        }
        config = nil
    }
    func loadAPIKey() throws -> String? {
        loadAPIKeyCallCount += 1
        guard let config else { return nil }
        return storedKeys[config.id]
    }
    func loadAPIKey(for provider: LLMProviderID) throws -> String? {
        loadAPIKeyCallCount += 1
        return storedKeys[provider]
    }

    func saveAPIKey(_ key: String) throws {
        guard let existing = config else { return }
        storedKeys[existing.id] = key
        config = LLMProviderConfig(
            id: existing.id, baseURL: existing.baseURL, apiKey: key,
            modelName: existing.modelName, isLocal: existing.isLocal
        )
    }

    func deleteAPIKey() throws {
        guard let existing = config else { return }
        storedKeys.removeValue(forKey: existing.id)
        config = LLMProviderConfig(
            id: existing.id, baseURL: existing.baseURL, apiKey: nil,
            modelName: existing.modelName, isLocal: existing.isLocal
        )
    }

    func updateModelName(_ modelName: String) throws {
        guard let existing = config else { return }
        config = LLMProviderConfig(
            id: existing.id, baseURL: existing.baseURL, apiKey: existing.apiKey,
            modelName: modelName, isLocal: existing.isLocal
        )
    }
}

private final class LLMTelemetrySpy: TelemetryServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TelemetryEventSpec] = []

    func send(_ event: TelemetryEventSpec) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool {
        send(event)
        return true
    }

    func flush() async {}
    func clearQueue() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }
    func flushForTermination() {}

    func snapshot() -> [TelemetryEventSpec] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

final class LLMServiceTests: XCTestCase {
    var mockClient: MockLLMClient!
    var mockConfigStore: MockLLMConfigStore!
    var mockContextResolver: MockLLMExecutionContextResolver!
    var service: LLMService!

    override func setUp() {
        mockClient = MockLLMClient()
        mockConfigStore = MockLLMConfigStore()
        mockConfigStore.config = .openai(apiKey: "sk-test")
        mockContextResolver = MockLLMExecutionContextResolver(configStore: mockConfigStore)
        service = LLMService(client: mockClient, contextResolver: mockContextResolver)
    }

    override func tearDown() {
        Telemetry.configure(NoOpTelemetryService())
        service = nil
        mockContextResolver = nil
        mockConfigStore = nil
        mockClient = nil
        super.tearDown()
    }

    // MARK: - Not Configured

    func testThrowsNotConfiguredWhenNoProvider() async {
        mockConfigStore.config = nil

        do {
            _ = try await service.summarize(transcript: "Test")
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testChatThrowsNotConfiguredWhenNoProvider() async {
        mockConfigStore.config = nil

        do {
            _ = try await service.chat(
                question: "Q", transcript: "T", userNotes: nil, history: [], source: .transcriptChat)
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransformThrowsNotConfiguredWhenNoProvider() async {
        mockConfigStore.config = nil

        do {
            _ = try await service.transform(text: "T", prompt: "P")
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFormatTranscriptThrowsNotConfiguredWhenNoProvider() async {
        mockConfigStore.config = nil

        do {
            _ = try await service.formatTranscript(
                transcript: "T",
                promptTemplate: "P",
                source: .dictation,
                defaultPromptUsed: true
            )
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetupCancellationEmitsCancelledLLMOperationWithoutErrorType() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockContextResolver.resolveError = CancellationError()

        do {
            _ = try await service.summarize(transcript: "Test")
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let operations = llmOperationProps(in: telemetry.snapshot())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?["feature"], "prompt_result")
        XCTAssertEqual(operations.first?["provider"], "unknown")
        XCTAssertEqual(operations.first?["streaming"], "false")
        XCTAssertEqual(operations.first?["outcome"], "cancelled")
        XCTAssertNil(operations.first?["error_type"])
    }

    // MARK: - Summarize

    func testSummarizeAssemblesCorrectPrompt() async throws {
        _ = try await service.summarize(transcript: "The meeting discussed budgets.")

        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertEqual(mockClient.capturedMessages[0].role, .system)
        XCTAssertTrue(mockClient.capturedMessages[0].content.contains("Summarize this transcript"))
        XCTAssertEqual(mockClient.capturedMessages[1].role, .user)
        XCTAssertEqual(mockClient.capturedMessages[1].content, "The meeting discussed budgets.")
    }

    // MARK: - Chat

    func testChatAssemblesSystemPromptWithTranscript() async throws {
        _ = try await service.chat(
            question: "What was discussed?",
            transcript: "We talked about the release.",
            userNotes: nil,
            history: [],
            source: .transcriptChat
        )

        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertEqual(mockClient.capturedMessages[0].role, .system)
        XCTAssertTrue(mockClient.capturedMessages[0].content.contains("We talked about the release."))
        XCTAssertEqual(mockClient.capturedMessages[1].role, .user)
        XCTAssertEqual(mockClient.capturedMessages[1].content, "What was discussed?")
    }

    func testChatIncludesHistory() async throws {
        let history = [
            ChatMessage(role: .user, content: "Who spoke?"),
            ChatMessage(role: .assistant, content: "Alice and Bob."),
        ]

        _ = try await service.chat(
            question: "What did Alice say?",
            transcript: "Alice said hello.",
            userNotes: nil,
            history: history,
            source: .transcriptChat
        )

        // system + 2 history + user question = 4
        XCTAssertEqual(mockClient.capturedMessages.count, 4)
        XCTAssertEqual(mockClient.capturedMessages[1].role, .user)
        XCTAssertEqual(mockClient.capturedMessages[1].content, "Who spoke?")
        XCTAssertEqual(mockClient.capturedMessages[2].role, .assistant)
        XCTAssertEqual(mockClient.capturedMessages[3].role, .user)
        XCTAssertEqual(mockClient.capturedMessages[3].content, "What did Alice say?")
    }

    func testChatInjectsUserNotesIntoSystemPromptWhenPresent() async throws {
        _ = try await service.chat(
            question: "Why did we delay?",
            transcript: "Alice: We're slipping by a week.",
            userNotes: "decision: ship Friday\nQA owns smoke tests",
            history: [],
            source: .transcriptChat
        )

        let systemPrompt = mockClient.capturedMessages[0].content
        XCTAssertTrue(systemPrompt.contains("User's notes from the meeting"))
        XCTAssertTrue(systemPrompt.contains("decision: ship Friday"))
        XCTAssertTrue(systemPrompt.contains("QA owns smoke tests"))
        // The notes block must precede the transcript block — the LLM reads
        // them as context for what the user cares about, applied while reading
        // the transcript that follows.
        let notesIdx = systemPrompt.range(of: "User's notes from the meeting")!.lowerBound
        let transcriptIdx = systemPrompt.range(of: "Transcript:")!.lowerBound
        XCTAssertLessThan(notesIdx, transcriptIdx)
    }

    func testChatOmitsUserNotesBlockWhenNotesAreNil() async throws {
        _ = try await service.chat(
            question: "Q",
            transcript: "T",
            userNotes: nil,
            history: [],
            source: .transcriptChat
        )
        XCTAssertFalse(
            mockClient.capturedMessages[0].content.contains("User's notes from the meeting"),
            "Nil userNotes must not introduce the notes block"
        )
    }

    func testChatOmitsUserNotesBlockWhenNotesAreEmpty() async throws {
        _ = try await service.chat(
            question: "Q",
            transcript: "T",
            userNotes: "",
            history: [],
            source: .transcriptChat
        )
        XCTAssertFalse(
            mockClient.capturedMessages[0].content.contains("User's notes from the meeting"),
            "Empty userNotes must not introduce the notes block"
        )
    }

    func testChatOmitsUserNotesBlockWhenNotesAreWhitespaceOnly() async throws {
        _ = try await service.chat(
            question: "Q",
            transcript: "T",
            userNotes: "   \n\t  \n  ",
            history: [],
            source: .transcriptChat
        )
        XCTAssertFalse(
            mockClient.capturedMessages[0].content.contains("User's notes from the meeting"),
            "Whitespace-only userNotes must not introduce the notes block"
        )
    }

    func testChatWithNilNotesIsByteIdenticalToOmittedBlock() async throws {
        _ = try await service.chat(
            question: "Q",
            transcript: "T",
            userNotes: nil,
            history: [],
            source: .transcriptChat
        )
        let withoutNotes = mockClient.capturedMessages[0].content

        // Re-init the mock and exercise with empty/whitespace notes; output
        // should be identical to the nil-notes case (no degraded behavior for
        // chats where the user simply hasn't typed during the meeting).
        mockClient.capturedMessages = []
        _ = try await service.chat(
            question: "Q",
            transcript: "T",
            userNotes: "   ",
            history: [],
            source: .transcriptChat
        )
        let withWhitespace = mockClient.capturedMessages[0].content
        XCTAssertEqual(withoutNotes, withWhitespace)
    }

    // MARK: - Detailed (Envelope) Variants

    func testSummarizeDetailedReturnsEnvelopeWithUsageAndModel() async throws {
        mockClient.responseContent = "summary"
        mockClient.responseModel = "gpt-4.1"
        mockClient.responseFinishReason = "stop"
        mockClient.responseUsage = TokenUsage(promptTokens: 50, completionTokens: 75)

        let result = try await service.summarizeDetailed(transcript: "hello world")

        XCTAssertEqual(result.output, "summary")
        XCTAssertEqual(result.model, "gpt-4.1")
        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.usage?.promptTokens, 50)
        XCTAssertEqual(result.usage?.completionTokens, 75)
        XCTAssertEqual(result.usage?.totalTokens, 125)
        XCTAssertEqual(result.stopReason, "stop")
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0)
    }

    func testSummarizeStringDelegatesToDetailed() async throws {
        // The string variant must end up in the same network call site as
        // detailed — proven by the call only landing once on the mock and
        // the captured user message matching what summarize() would assemble.
        mockClient.responseContent = "delegated"

        let output = try await service.summarize(transcript: "input text")

        XCTAssertEqual(output, "delegated")
        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertEqual(mockClient.capturedMessages[1].content, "input text")
    }

    func testChatDetailedReturnsEnvelope() async throws {
        mockClient.responseContent = "answer"
        mockClient.responseModel = "claude-sonnet-4-6"
        mockClient.responseUsage = TokenUsage(promptTokens: 200, completionTokens: 30)

        let result = try await service.chatDetailed(
            question: "Who?",
            transcript: "Alice and Bob spoke.",
            userNotes: nil,
            history: [],
            source: .transcriptChat
        )

        XCTAssertEqual(result.output, "answer")
        XCTAssertEqual(result.model, "claude-sonnet-4-6")
        XCTAssertEqual(result.usage?.totalTokens, 230)
    }

    func testTransformDetailedReturnsEnvelopeWithoutUsageWhenAbsent() async throws {
        mockClient.responseContent = "TRANSFORMED"
        mockClient.responseModel = "qwen-4b"
        mockClient.responseUsage = nil

        let result = try await service.transformDetailed(text: "hello", prompt: "uppercase")

        XCTAssertEqual(result.output, "TRANSFORMED")
        XCTAssertEqual(result.model, "qwen-4b")
        XCTAssertNil(result.usage)
    }

    func testFormatTranscriptDetailedReturnsEnvelopeAndFormatterMetadata() async throws {
        mockClient.responseContent = "Hello, world."
        mockClient.responseModel = "formatter-model"
        mockClient.responseFinishReason = "stop"
        mockClient.responseUsage = TokenUsage(promptTokens: 11, completionTokens: 4)

        let result = try await service.formatTranscriptDetailed(
            transcript: "hello world",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .dictation,
            defaultPromptUsed: true
        )

        XCTAssertEqual(result.output, "Hello, world.")
        XCTAssertEqual(result.result.provider, "openai")
        XCTAssertEqual(result.result.model, "formatter-model")
        XCTAssertEqual(result.result.usage?.promptTokens, 11)
        XCTAssertEqual(result.result.usage?.completionTokens, 4)
        XCTAssertEqual(result.result.usage?.totalTokens, 15)
        XCTAssertEqual(result.result.stopReason, "stop")
        XCTAssertFalse(result.operationID.isEmpty)
        XCTAssertEqual(result.inputChars, "hello world".count)
        XCTAssertEqual(result.outputChars, "Hello, world.".count)
        XCTAssertFalse(result.inputTruncated)
        XCTAssertTrue(result.defaultPromptUsed)
        XCTAssertEqual(result.messageCount, 2)
    }

    func testFormatTranscriptDetailedPreservesTranscriptWithLargePrompt() async throws {
        mockConfigStore.config = .ollama(model: "llama3.2")
        let transcript = "SENTINEL_TRANSCRIPT"
        let longPromptTemplate =
            String(repeating: "instruction ", count: 9_000)
            + AIFormatter.transcriptPlaceholder

        let result = try await service.formatTranscriptDetailed(
            transcript: transcript,
            promptTemplate: longPromptTemplate,
            source: .dictation,
            defaultPromptUsed: false
        )

        XCTAssertFalse(result.inputTruncated)
        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains(transcript))
        XCTAssertTrue(
            mockClient.capturedMessages[1].content.contains(
                longPromptTemplate.replacingOccurrences(
                    of: AIFormatter.transcriptPlaceholder,
                    with: transcript
                )))
    }

    // MARK: - Transform

    func testTransformAssemblesCorrectPrompt() async throws {
        _ = try await service.transform(text: "hello world", prompt: "Make it uppercase")

        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertEqual(mockClient.capturedMessages[0].role, .system)
        XCTAssertTrue(mockClient.capturedMessages[0].content.contains("transforms text"))
        XCTAssertEqual(mockClient.capturedMessages[1].role, .user)
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains("Make it uppercase"))
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains("hello world"))
    }

    func testFormatTranscriptRendersPromptTemplateWithTranscriptPlaceholder() async throws {
        _ = try await service.formatTranscript(
            transcript: "hello world",
            promptTemplate: "Clean this transcript:\n\(AIFormatter.transcriptPlaceholder)",
            source: .dictation,
            defaultPromptUsed: false
        )

        XCTAssertEqual(mockClient.capturedMessages.count, 2)
        XCTAssertEqual(mockClient.capturedMessages[0].role, .system)
        XCTAssertTrue(mockClient.capturedMessages[0].content.contains("formatted transcript"))
        XCTAssertEqual(mockClient.capturedMessages[1].role, .user)
        XCTAssertEqual(mockClient.capturedMessages[1].content, "Clean this transcript:\nhello world")
    }

    func testFormatTranscriptForLMStudioUsesStructuredOutputFromReasoningContent() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        mockClient.responseContent = ""
        mockClient.responseReasoningContent = #"{"cleaned_text":"Hello world. This is a test."}"#

        let result = try await service.formatTranscript(
            transcript: "hello world this is a test",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .dictation,
            defaultPromptUsed: true
        )

        XCTAssertEqual(result, "Hello world. This is a test.")
        XCTAssertEqual(
            mockClient.capturedOptions?.responseFormat,
            .jsonSchema(
                name: "formatter_output",
                schema: ChatJSONSchema(
                    type: "object",
                    properties: [
                        "cleaned_text": ChatJSONSchemaProperty(type: "string")
                    ],
                    required: ["cleaned_text"],
                    additionalProperties: false
                )
            )
        )
    }

    func testMeetingReadingTurnBatchForLMStudioUsesMatchingSchemaAndReturnsRawJSON() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        let response = #"{"entries":[{"id":"turn-0","text":"First.\nSecond."}]}"#
        mockClient.responseContent = response

        let result = try await service.formatTranscriptDetailed(
            transcript: #"{"entries":[{"id":"turn-0","text":"first second"}]}"#,
            promptTemplate: MeetingReadingTurnFormatter.promptTemplate(AIFormatter.defaultPromptTemplate),
            source: .transcription,
            defaultPromptUsed: true,
            diagnosticID: UUID(),
            responseContract: .meetingReadingTurnBatch
        )

        XCTAssertEqual(result.output, response)
        XCTAssertEqual(
            mockClient.capturedOptions?.responseFormat,
            .jsonSchema(
                name: "meeting_reading_turn_batch",
                schema: LLMService.meetingReadingTurnBatchSchema
            )
        )
    }

    func testFormatTranscriptForLMStudioNormalizesEscapedParagraphBreaks() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        mockClient.responseContent = ""
        mockClient.responseReasoningContent =
            #"{"cleaned_text":"First paragraph.\\nSecond paragraph.\\nThird paragraph."}"#

        let result = try await service.formatTranscript(
            transcript: "first paragraph second paragraph third paragraph",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .dictation,
            defaultPromptUsed: true
        )

        XCTAssertEqual(result, "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.")
    }

    func testFormatTranscriptForLMStudioPreservesParagraphsWhenOutputMixesRealAndEscapedNewlines() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        mockClient.responseContent = ""
        mockClient.responseReasoningContent =
            #"{"cleaned_text":"Intro line.\nSecond line in same paragraph.\\nNew paragraph starts here."}"#

        let result = try await service.formatTranscript(
            transcript: "intro and follow-up then new paragraph",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .dictation,
            defaultPromptUsed: true
        )

        XCTAssertEqual(result, "Intro line.\nSecond line in same paragraph.\n\nNew paragraph starts here.")
    }

    func testMeetingFormatterUsesLongRequestTimeout() async throws {
        _ = try await service.formatTranscriptDetailed(
            transcript: "Complete meeting transcript.",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .transcription,
            defaultPromptUsed: true,
            diagnosticID: UUID()
        )

        XCTAssertEqual(
            mockClient.capturedOptions?.requestTimeoutSeconds,
            LLMService.meetingFormatterRequestTimeoutSeconds
        )
    }

    func testRegularFormatterKeepsProviderDefaultRequestTimeout() async throws {
        _ = try await service.formatTranscriptDetailed(
            transcript: "Short dictation.",
            promptTemplate: AIFormatter.defaultPromptTemplate,
            source: .dictation,
            defaultPromptUsed: true
        )

        XCTAssertNil(mockClient.capturedOptions?.requestTimeoutSeconds)
    }

    func testMeetingDiagnosticsCaptureProviderResponseBeforeRejectionOrNormalization() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio, baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil, modelName: "local-model", isLocal: true
        )
        let cases: [(String, String?, String, Bool)] = [
            (#"{"cleaned_text":"Partial output"}"#, nil, "length", true),
            ("", #"{"cleaned_text":"   \n  "}"#, "stop", true),
            (#"{"cleaned_text":"Hello.\\nWorld."}"#, nil, "stop", false),
        ]
        for (content, reasoning, stop, shouldFail) in cases {
            let id = UUID()
            mockClient.responseContent = content
            mockClient.responseReasoningContent = reasoning
            mockClient.responseFinishReason = stop
            do {
                _ = try await service.formatTranscriptDetailed(
                    transcript: "Complete source transcript.",
                    promptTemplate: AIFormatter.defaultPromptTemplate,
                    source: .transcription, defaultPromptUsed: true, diagnosticID: id
                )
                XCTAssertFalse(shouldFail)
            } catch {
                XCTAssertTrue(shouldFail, "\(error)")
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "MacParakeetTests/meeting-ai-cleanup-\(ProcessInfo.processInfo.processIdentifier).jsonl"
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let events = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                try decoder.decode(MeetingFormattingDiagnostic.self, from: Data($0.utf8))
            }
            let event = try XCTUnwrap(events.first { $0.id == id })
            XCTAssertEqual(event.outcome, "provider_response")
            XCTAssertEqual(event.output, content)
            XCTAssertEqual(event.reasoningContent, reasoning)
            XCTAssertTrue(event.input.contains("Complete source transcript."))
            XCTAssertTrue(event.reason?.contains("stop_reason=\(stop)") == true)
        }
    }

    func testFormatTranscriptForLMStudioThrowsWhenOutputIsTruncated() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        mockClient.responseContent = #"{"cleaned_text":"Partial output"}"#
        mockClient.responseFinishReason = "length"

        do {
            _ = try await service.formatTranscript(
                transcript: "long transcript content",
                promptTemplate: AIFormatter.defaultPromptTemplate,
                source: .dictation,
                defaultPromptUsed: true
            )
            XCTFail("Expected truncated formatter output to throw")
        } catch let error as LLMError {
            if case .formatterTruncated = error {
                // Expected
            } else {
                XCTFail("Expected formatterTruncated, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFormatTranscriptForLMStudioThrowsWhenResponseIsEmpty() async throws {
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        // Cold-start LM Studio reasoning models can return an empty body or
        // whitespace-only content. We should route those through the failure
        // path so the success-rate metric isn't inflated with runs that
        // produced nothing usable.
        mockClient.responseContent = ""
        mockClient.responseReasoningContent = #"{"cleaned_text":"   \n  "}"#

        do {
            _ = try await service.formatTranscript(
                transcript: "hello world",
                promptTemplate: AIFormatter.defaultPromptTemplate,
                source: .dictation,
                defaultPromptUsed: true
            )
            XCTFail("Expected empty formatter output to throw")
        } catch let error as LLMError {
            if case .formatterEmptyResponse = error {
                // Expected
            } else {
                XCTFail("Expected formatterEmptyResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Complete Context

    func testFormerProviderBudgetsDoNotReducePromptResultInput() async throws {
        let source = sentinelText(repeating: "source", count: 70_000)
        let prompt = sentinelText(repeating: "instruction", count: 4_000)
        let providers: [LLMProviderConfig] = [
            .openai(apiKey: "sk-test"),
            .ollama(model: "llama3.2"),
            .lmstudio(model: "qwen/qwen3-4b-2507"),
            ]

        for provider in providers {
            mockConfigStore.config = provider
            _ = try await service.generatePromptResultDetailed(transcript: source, systemPrompt: prompt)

            XCTAssertEqual(mockClient.capturedMessages[0].content, prompt)
            XCTAssertEqual(mockClient.capturedMessages[1].content, source)
            XCTAssertFalse(mockClient.capturedMessages.contains { $0.content.contains("content truncated") })
        }
        }

    func testChatSendsCompleteTranscriptNotesQuestionAndOldHistory() async throws {
        mockConfigStore.config = .lmstudio(model: "small-former-budget")
        let transcript = sentinelText(repeating: "transcript", count: 12_000)
        let notes = sentinelText(repeating: "notes", count: 4_000)
        let question = sentinelText(repeating: "question", count: 2_000)
        let oldestOverride = "OLD_OVERRIDE_SENTINEL " + String(repeating: "override ", count: 2_000)
        let history = [
            ChatMessage(role: .user, content: "old label", modelPromptOverride: oldestOverride),
            ChatMessage(role: .assistant, content: "OLD_ASSISTANT_SENTINEL"),
            ChatMessage(role: .user, content: "RECENT_USER_SENTINEL"),
            ChatMessage(role: .assistant, content: "RECENT_ASSISTANT_SENTINEL"),
        ]

        _ = try await service.chat(
            question: question,
            transcript: transcript,
            userNotes: notes,
            history: history,
            source: .meetingAsk
        )

        XCTAssertTrue(mockClient.capturedMessages[0].content.contains(transcript))
        XCTAssertTrue(mockClient.capturedMessages[0].content.contains(notes))
        XCTAssertEqual(
            Array(mockClient.capturedMessages.dropFirst().dropLast()),
            [
                ChatMessage(role: .user, content: oldestOverride),
                history[1], history[2], history[3],
            ])
        XCTAssertEqual(mockClient.capturedMessages.last?.content, question)
    }

    func testFormatterAndTransformSendCompleteInputs() async throws {
        mockConfigStore.config = .lmstudio(model: "small-former-budget")
        mockClient.responseContent = #"{"cleaned_text":"formatted"}"#
        let transcript = sentinelText(repeating: "formatter", count: 12_000)
        let template =
            "PROMPT_BEGIN\n" + String(repeating: "instruction ", count: 2_000)
            + "\n{{TRANSCRIPT}}\nPROMPT_END"

        _ = try await service.formatTranscriptDetailed(
            transcript: transcript,
            promptTemplate: template,
            source: .transcription,
            defaultPromptUsed: false
        )
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains(transcript))
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains("PROMPT_BEGIN"))
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains("PROMPT_END"))

        let text = sentinelText(repeating: "transform", count: 12_000)
        let prompt = sentinelText(repeating: "transform-prompt", count: 2_000)
        _ = try await service.transformDetailed(text: text, prompt: prompt)
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains(text))
        XCTAssertTrue(mockClient.capturedMessages[1].content.contains(prompt))
    }

    func testContextLimitErrorIsReturnedWithoutReducedRetry() async {
        mockClient.chatCompletionError = LLMError.contextTooLong

        do {
            _ = try await service.summarize(transcript: sentinelText(repeating: "source", count: 70_000))
            XCTFail("Expected contextTooLong")
        } catch let error as LLMError {
            guard case .contextTooLong = error else {
                return XCTFail("Expected contextTooLong, got \(error)")
            }
            XCTAssertEqual(
                error.localizedDescription,
                "The complete text exceeds the configured model's context limit. Select a model with a larger context window."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(mockClient.chatCompletionCallCount, 1)
    }

    private func sentinelText(repeating word: String, count: Int) -> String {
        "BEGIN_SENTINEL " + String(repeating: "\(word) ", count: count / 2)
            + "MIDDLE_SENTINEL " + String(repeating: "\(word) ", count: count / 2)
            + "END_SENTINEL"
    }

    // MARK: - Streaming

    func testSummarizeStreamYieldsTokens() async throws {
        mockClient.streamTokens = ["Hello", " ", "world"]
        let stream = service.summarizeStream(transcript: "Test transcript")

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Hello", " ", "world"])
    }

    func testChatStreamYieldsTokens() async throws {
        mockClient.streamTokens = ["Chat", " ", "response"]
        let stream = service.chatStream(
            question: "What happened?",
            transcript: "Something happened.",
            userNotes: nil,
            history: [],
            source: .transcriptChat
        )

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Chat", " ", "response"])
    }

    func testTransformStreamYieldsTokens() async throws {
        mockClient.streamTokens = ["HELLO", " ", "WORLD"]
        let stream = service.transformStream(text: "hello world", prompt: "uppercase")

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["HELLO", " ", "WORLD"])
    }

    func testSummarizeStreamThrowsWhenNotConfigured() async {
        mockConfigStore.config = nil
        let stream = service.summarizeStream(transcript: "Test")

        do {
            for try await _ in stream {
                XCTFail("Expected stream to throw")
            }
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSummarizeStreamSetupCancellationEmitsOneCancelledLLMOperationWithoutErrorType() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockContextResolver.resolveError = CancellationError()
        let stream = service.summarizeStream(transcript: "Test")

        do {
            for try await _ in stream {
                XCTFail("Expected stream to throw")
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let events = telemetry.snapshot()
        let operations = llmOperationProps(in: events)
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?["feature"], "prompt_result")
        XCTAssertEqual(operations.first?["provider"], "unknown")
        XCTAssertEqual(operations.first?["streaming"], "true")
        XCTAssertEqual(operations.first?["outcome"], "cancelled")
        XCTAssertNil(operations.first?["error_type"])
        XCTAssertFalse(
            events.contains { event in
            if case .llmPromptResultFailed = event { return true }
            return false
        })
    }

    func testChatStreamThrowsWhenNotConfigured() async {
        mockConfigStore.config = nil
        let stream = service.chatStream(
            question: "Q", transcript: "T", userNotes: nil, history: [], source: .transcriptChat)

        do {
            for try await _ in stream {
                XCTFail("Expected stream to throw")
            }
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransformStreamThrowsWhenNotConfigured() async {
        mockConfigStore.config = nil
        let stream = service.transformStream(text: "T", prompt: "P")

        do {
            for try await _ in stream {
                XCTFail("Expected stream to throw")
            }
            XCTFail("Expected LLMError.notConfigured")
        } catch let error as LLMError {
            if case .notConfigured = error {
            } else {
                XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Provider-Unavailable Routing
    //
    // Persistent user-environment errors (Ollama down, model name typo,
    // missing CLI, bad API key) are emitted as `llm_provider_unavailable`
    // instead of `llm_*_failed`. The `*_failed` buckets should reflect real
    // failures worth investigating, not "this user's Ollama isn't running."

    func testFormatTranscriptEmitsProviderUnavailableOnConnectionFailed() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .ollama,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            apiKey: nil,
            modelName: "llama3:8b",
            isLocal: true
        )
        mockClient.chatCompletionError = LLMError.connectionFailed("refused")

        do {
            _ = try await service.formatTranscript(
                transcript: "hello",
                promptTemplate: AIFormatter.defaultPromptTemplate,
                source: .dictation,
                defaultPromptUsed: true
            )
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, let errorType, let feature, let source) = event {
                return provider == "ollama"
                    && errorType == "LLMError.connectionFailed"
                    && feature == .formatter
                    && source == .dictation
            }
            return false
        }, "Expected llmProviderUnavailable in: \(events)")
        XCTAssertFalse(
            events.contains { event in
            if case .llmFormatterFailed = event { return true }
            return false
        }, "Expected NO llmFormatterFailed (user-config errors should not pollute the failure bucket)")
    }

    func testFormatTranscriptStillEmitsFormatterFailedOnRealFailure() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .lmstudio,
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelName: "qwen3.5-4b-mlx",
            isLocal: true
        )
        mockClient.responseContent = "ignored"
        mockClient.responseFinishReason = "length"

        do {
            _ = try await service.formatTranscript(
                transcript: "hello",
                promptTemplate: AIFormatter.defaultPromptTemplate,
                source: .dictation,
                defaultPromptUsed: true
            )
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmFormatterFailed = event { return true }
            return false
        }, "Real formatter failures (truncation, etc.) should still emit llmFormatterFailed")
        XCTAssertFalse(
            events.contains { event in
            if case .llmProviderUnavailable = event { return true }
            return false
        })
    }

    func testGeneratePromptResultEmitsProviderUnavailableOnModelNotFound() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .ollama,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            apiKey: nil,
            modelName: "missing-model",
            isLocal: true
        )
        mockClient.chatCompletionError = LLMError.modelNotFound("missing-model")

        do {
            _ = try await service.generatePromptResult(transcript: "hi", systemPrompt: nil)
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, let errorType, let feature, _) = event {
                return provider == "ollama"
                    && errorType == "LLMError.modelNotFound"
                    && feature == .promptResult
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmPromptResultFailed = event { return true }
            return false
        })
    }

    func testChatEmitsProviderUnavailableOnCLIError() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .localCLI,
            baseURL: URL(string: "file:///usr/local/bin/llm")!,
            apiKey: nil,
            modelName: "claude",
            isLocal: false
        )
        mockClient.chatCompletionError = LLMError.cliError("not found")

        do {
            _ = try await service.chat(
                question: "Q", transcript: "T", userNotes: nil, history: [], source: .transcriptChat)
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, let errorType, let feature, let source) = event {
                return provider == "localCLI"
                    && errorType == "LLMError.cliError"
                    && feature == .chat
                    && source == .transcriptChat
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmChatFailed = event { return true }
            return false
        })
        XCTAssertEqual(llmOperationProps(in: events).first?["outcome"], "unavailable")
    }

    func testTransformEmitsProviderUnavailableOnAuthFailed() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = .anthropic(apiKey: "bad-key")
        mockClient.chatCompletionError = LLMError.authenticationFailed(nil)

        do {
            _ = try await service.transform(text: "T", prompt: "P")
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, let errorType, let feature, _) = event {
                return provider == "anthropic"
                    && errorType == "LLMError.authenticationFailed"
                    && feature == .transform
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmTransformFailed = event { return true }
            return false
        })
    }

    func testStreamingPromptResultEmitsProviderUnavailableOnConnectionFailed() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .ollama,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            apiKey: nil,
            modelName: "llama3:8b",
            isLocal: true
        )
        mockClient.chatCompletionError = LLMError.connectionFailed("refused")
        let stream = service.generatePromptResultStream(transcript: "hi", systemPrompt: nil)

        do {
            for try await _ in stream {}
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, _, let feature, _) = event {
                return provider == "ollama" && feature == .promptResult
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmPromptResultFailed = event { return true }
            return false
        })
    }

    func testStreamingChatEmitsProviderUnavailableOnModelNotFound() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = LLMProviderConfig(
            id: .ollama,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            apiKey: nil,
            modelName: "missing",
            isLocal: true
        )
        mockClient.chatCompletionError = LLMError.modelNotFound("missing")
        let stream = service.chatStream(
            question: "Q", transcript: "T", userNotes: nil, history: [], source: .transcriptChat)

        do {
            for try await _ in stream {}
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, _, let feature, let source) = event {
                return provider == "ollama" && feature == .chat && source == .transcriptChat
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmChatFailed = event { return true }
            return false
        })
        XCTAssertEqual(llmOperationProps(in: events).first?["outcome"], "unavailable")
    }

    func testStreamingTransformEmitsProviderUnavailableOnAuthFailed() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = .anthropic(apiKey: "bad-key")
        mockClient.chatCompletionError = LLMError.authenticationFailed(nil)
        let stream = service.transformStream(text: "T", prompt: "P")

        do {
            for try await _ in stream {}
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmProviderUnavailable(let provider, _, let feature, _) = event {
                return provider == "anthropic" && feature == .transform
            }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmTransformFailed = event { return true }
            return false
        })
    }

    func testProviderErrorStillRoutedToLegacyFailedBucket() async {
        let telemetry = LLMTelemetrySpy()
        Telemetry.configure(telemetry)
        mockConfigStore.config = .openai(apiKey: "sk-test")
        // providerError indicates an API-side failure with a message; the
        // user's environment is fine. This should stay in llm_chat_failed,
        // not get reclassified as user-config drift.
        mockClient.chatCompletionError = LLMError.providerError("500 Internal")

        do {
            _ = try await service.chat(
                question: "Q", transcript: "T", userNotes: nil, history: [], source: .transcriptChat)
            XCTFail("Expected throw")
        } catch {}

        let events = telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
            if case .llmChatFailed = event { return true }
            return false
        })
        XCTAssertFalse(
            events.contains { event in
            if case .llmProviderUnavailable = event { return true }
            return false
        })
    }

    // MARK: - Model Selection

    func testUpdateModelNamePreservesProviderAndBaseURL() throws {
        mockConfigStore.config = .openai(apiKey: "sk-test", model: "gpt-5.4")

        try mockConfigStore.updateModelName("gpt-5-mini")

        let config = try mockConfigStore.loadConfig()
        XCTAssertEqual(config?.modelName, "gpt-5-mini")
        XCTAssertEqual(config?.id, .openai)
        XCTAssertEqual(config?.apiKey, "sk-test")
        XCTAssertEqual(config?.isLocal, false)
    }

    func testUpdateModelNameOnNilConfigIsNoOp() throws {
        mockConfigStore.config = nil
        try mockConfigStore.updateModelName("gpt-5-mini")
        XCTAssertNil(try mockConfigStore.loadConfig())
    }

    private func llmOperationProps(in events: [TelemetryEventSpec]) -> [[String: String]] {
        events.compactMap { event in
            guard case .llmOperation = event else { return nil }
            return event.props ?? [:]
        }
    }
}
