@preconcurrency import AVFoundation
import os
import XCTest
@testable import MacParakeetCore

final class MicrophoneEnginePlatformStartupReadinessTests: XCTestCase {
    func testFailedEngineIsReleasedBeforeFallbackWithoutConfigurationNotification() throws {
        try assertFailedEngineIsReleasedBeforeFallback(postConfigurationChange: false)
    }

    func testFailedEngineIsReleasedBeforeFallbackWithQueuedConfigurationNotification() throws {
        try assertFailedEngineIsReleasedBeforeFallback(postConfigurationChange: true)
    }

    private func assertFailedEngineIsReleasedBeforeFallback(postConfigurationChange: Bool) throws {
        let failedEngine = OSAllocatedUnfairLock<WeakReadinessEngine?>(initialState: nil)
        let starts = OSAllocatedUnfairLock(initialState: 0)
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    .implicitSystemDefault(resolvedDeviceID: 10),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            bluetoothInputState: { $0 == 10 },
            engineStarter: { engine, _, _, tapHandler in
                let start = starts.withLock { count in
                    count += 1
                    return count
                }
                if start == 1 {
                    failedEngine.withLock { $0 = WeakReadinessEngine(engine) }
                    if postConfigurationChange {
                        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
                    }
                    throw NSError(domain: NSOSStatusErrorDomain, code: -10868)
                }
                XCTAssertNil(
                    failedEngine.withLock { $0?.engine },
                    "A queued notification must not keep the failed engine alive while fallback starts"
                )
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
        XCTAssertEqual(starts.withLock { $0 }, 2)
    }

    func testConfigurationRecoveryReleasesOldEngineBeforeStartingReplacement() throws {
        let oldEngine = OSAllocatedUnfairLock<WeakReadinessEngine?>(initialState: nil)
        let starts = OSAllocatedUnfairLock(initialState: 0)
        let replacementStarted = expectation(description: "replacement starts without retaining old engine")
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            engineStarter: { engine, _, _, tapHandler in
                let start = starts.withLock { count in
                    count += 1
                    return count
                }
                if start == 1 {
                    oldEngine.withLock { $0 = WeakReadinessEngine(engine) }
                    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
                } else {
                    XCTAssertNil(oldEngine.withLock { $0?.engine }, "Recovery must not retain the retired engine")
                    replacementStarted.fulfill()
                }
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
        wait(for: [replacementStarted], timeout: 1)
        XCTAssertTrue(platform.isEngineRunning)
        XCTAssertEqual(starts.withLock { $0 }, 2)
    }

    func testReadinessTimeoutRebuildsAndRetriesSameRouteBeforeFallback() throws {
        let selected = MeetingInputDeviceAttempt(source: .selected(uid: "bose"), deviceID: 10)
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let selectedDevices = OSAllocatedUnfairLock(initialState: [AudioDeviceID]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [selected, MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)]
            },
            inputDeviceSetter: { deviceID, _ in
                selectedDevices.withLock { $0.append(deviceID) }
                return true
            },
            startupReadinessTimeout: 0,
            bluetoothInputState: { $0 == 10 },
            engineStarter: { engine, _, _, tapHandler in
                let count = engines.withLock { engines in
                    engines.append(engine)
                    return engines.count
                }
                if count == 2 {
                    tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                }
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })

        XCTAssertEqual(selectedDevices.withLock { $0 }, [10, 10])
        XCTAssertEqual(platform.lastSucceededAttempt, selected)
        let startedEngines = engines.withLock { $0 }
        XCTAssertEqual(startedEngines.count, 2)
        XCTAssertFalse(startedEngines[0] === startedEngines[1])
    }

    func testReadinessFailureDoesNotCarryIntoNextSubscription() async throws {
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .selected(uid: "bose"), deviceID: 10)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in true },
            engineStarter: { engine, _, _, tapHandler in
                let count = engines.withLock { engines in
                    engines.append(engine)
                    return engines.count
                }
                // First subscription exhausts both attempts. The next one gets
                // its own reset budget and succeeds on its second engine.
                if count == 4 {
                    tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                }
            }
        )
        let stream = SharedMicrophoneStream(platform: platform, bufferSize: 256)

        do {
            _ = try await stream.subscribe(wantsVPIO: false) { _, _ in }
            XCTFail("Both readiness deadlines must expire before subscription fails")
        } catch let error as SharedMicrophoneStream.SubscribeError {
            guard case .engineStartFailed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(engines.withLock { $0.count }, 2)
        XCTAssertEqual(stream.diagnostics.subscriberCount, 0)
        XCTAssertFalse(stream.diagnostics.engineRunning)
        XCTAssertFalse(platform.isEngineRunning)
        XCTAssertNil(platform.lastSucceededAttempt)
        XCTAssertFalse(platform.preparedEngineStateForTesting.prepared)

        let token = try await stream.subscribe(wantsVPIO: false) { _, _ in }
        XCTAssertTrue(stream.diagnostics.engineRunning)
        XCTAssertEqual(stream.diagnostics.subscriberCount, 1)
        let startedEngines = engines.withLock { $0 }
        XCTAssertEqual(startedEngines.count, 4)
        XCTAssertEqual(Set(startedEngines.map(ObjectIdentifier.init)).count, 4)
        await stream.unsubscribe(token)
    }

    func testUnresolvedRouteReadinessTimeoutRebuildsBeforeFailing() throws {
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            startupReadinessTimeout: 0,
            engineStarter: { engine, _, _, tapHandler in
                let count = engines.withLock { engines in
                    engines.append(engine)
                    return engines.count
                }
                if count == 2 {
                    tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                }
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })

        XCTAssertTrue(platform.isEngineRunning)
        let startedEngines = engines.withLock { $0 }
        XCTAssertEqual(startedEngines.count, 2)
        XCTAssertFalse(startedEngines[0] === startedEngines[1])
    }

    func testPreparedReadinessTimeoutUsesOnlyOneFreshEngineRetry() {
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { engine, _, _, _ in
                engines.withLock { $0.append(engine) }
            }
        )
        defer { platform.stopEngine() }
        platform.prepare(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
        let preparedEngine = platform.preparedEngineStateForTesting.engine

        XCTAssertThrowsError(
            try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
        ) { error in
            XCTAssertEqual(error as? AVAudioEngineMicrophonePlatformError, .initialReadinessTimedOut)
        }

        let startedEngines = engines.withLock { $0 }
        XCTAssertEqual(startedEngines.count, 2, "Prepared start plus one reset, not a third readiness wait")
        XCTAssertTrue(startedEngines.first === preparedEngine)
        XCTAssertFalse(startedEngines.last === preparedEngine)
        XCTAssertFalse(platform.isEngineRunning)
        XCTAssertFalse(platform.preparedEngineStateForTesting.prepared)
    }

    func testEachEngineGetsItsOwnReadinessDeadline() {
        let startTimes = OSAllocatedUnfairLock(initialState: [TimeInterval]())
        let timeout: TimeInterval = 0.02
        let platform = AVAudioEngineMicrophonePlatform(
            startupReadinessTimeout: timeout,
            engineStarter: { _, _, _, _ in
                startTimes.withLock { $0.append(ProcessInfo.processInfo.systemUptime) }
            }
        )
        defer { platform.stopEngine() }

        XCTAssertThrowsError(
            try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
        ) { error in
            XCTAssertEqual(error as? AVAudioEngineMicrophonePlatformError, .initialReadinessTimedOut)
        }
        let endedAt = ProcessInfo.processInfo.systemUptime
        let times = startTimes.withLock { $0 }
        XCTAssertEqual(times.count, 2)
        guard times.count == 2 else { return }
        XCTAssertGreaterThanOrEqual(times[1] - times[0], timeout)
        XCTAssertGreaterThanOrEqual(endedAt - times[1], timeout)
        XCTAssertFalse(platform.isEngineRunning)
    }

    func testLateBufferFromTimedOutEngineCannotSatisfyRetryReadiness() {
        let previousHandler = OSAllocatedUnfairLock<SharedMicrophoneStream.BufferHandler?>(initialState: nil)
        let startCount = OSAllocatedUnfairLock(initialState: 0)
        let deliveredCount = OSAllocatedUnfairLock(initialState: 0)
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let platform = AVAudioEngineMicrophonePlatform(
            startupReadinessTimeout: 0,
            engineStarter: { _, _, _, tapHandler in
                startCount.withLock { $0 += 1 }
                let oldHandler = previousHandler.withLock { handler in
                    let old = handler
                    handler = tapHandler
                    return old
                }
                oldHandler?(buffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        XCTAssertThrowsError(
            try platform.configureAndStart(
                vpioEnabled: false,
                bufferSize: 256,
                tapHandler: { _, _ in deliveredCount.withLock { $0 += 1 } }
            )
        ) { error in
            XCTAssertEqual(error as? AVAudioEngineMicrophonePlatformError, .initialReadinessTimedOut)
        }

        XCTAssertEqual(startCount.withLock { $0 }, 2)
        XCTAssertEqual(deliveredCount.withLock { $0 }, 0)
        XCTAssertFalse(platform.isEngineRunning)
    }

    func testFormatErrorAfterReadinessResetDoesNotBlockNextStart() throws {
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let handlers = OSAllocatedUnfairLock(initialState: [SharedMicrophoneStream.BufferHandler]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))
        let deliveredCount = OSAllocatedUnfairLock(initialState: 0)
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .selected(uid: "bose"), deviceID: 10)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in true },
            engineStarter: { engine, _, _, tapHandler in
                handlers.withLock { $0.append(tapHandler) }
                let count = engines.withLock { engines in
                    engines.append(engine)
                    return engines.count
                }
                if count == 2 {
                    throw NSError(domain: NSOSStatusErrorDomain, code: -10868)
                }
                if count == 3 {
                    tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                }
            }
        )
        defer { platform.stopEngine() }
        let handler: SharedMicrophoneStream.BufferHandler = { _, _ in
            deliveredCount.withLock { $0 += 1 }
        }

        XCTAssertThrowsError(
            try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: handler)
        ) { error in
            XCTAssertEqual((error as NSError).code, -10868)
        }
        XCTAssertFalse(platform.isEngineRunning)
        XCTAssertNil(platform.inputFormat)

        try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: handler)
        let staleHandlers = handlers.withLock { Array($0.prefix(2)) }
        for staleHandler in staleHandlers {
            staleHandler(buffer.buffer, AVAudioTime(hostTime: 2))
        }

        XCTAssertTrue(platform.isEngineRunning)
        XCTAssertEqual(engines.withLock { Set($0.map(ObjectIdentifier.init)).count }, 3)
        XCTAssertEqual(deliveredCount.withLock { $0 }, 1, "Failed engines must not retain a live callback")
    }

    func testStartFallsBackWhenPreferredRouteProducesNoBuffer() throws {
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let engines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(
                        source: .selected(uid: "preferred"),
                        deviceID: 10
                    ),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { engine, _, _, tapHandler in
                let invocation = invocationCount.withLock { value -> Int in
                    value += 1
                    return value
                }
                engines.withLock { $0.append(engine) }
                if invocation == 3 {
                    tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                }
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        XCTAssertEqual(invocationCount.withLock { $0 }, 3)
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            .implicitSystemDefault(resolvedDeviceID: 20)
        )
        let startedEngines = engines.withLock { $0 }
        XCTAssertEqual(startedEngines.count, 3)
        XCTAssertEqual(Set(startedEngines.map(ObjectIdentifier.init)).count, 3)
    }

    func testStartFailsWhenNoRouteProducesABuffer() {
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(
                        source: .selected(uid: "preferred"),
                        deviceID: 10
                    ),
                    .implicitSystemDefault(resolvedDeviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { _, _, _, _ in
                invocationCount.withLock { $0 += 1 }
            }
        )

        XCTAssertThrowsError(
            try platform.configureAndStart(
                vpioEnabled: false,
                bufferSize: 256,
                tapHandler: { _, _ in }
            )
        ) { error in
            XCTAssertEqual(
                error as? AVAudioEngineMicrophonePlatformError,
                .initialReadinessTimedOut
            )
        }
        XCTAssertFalse(platform.isEngineRunning)
        XCTAssertEqual(invocationCount.withLock { $0 }, 4)
    }

    func testMissingRouteIdentityDoesNotAcceptZeroFilledBuffer() {
        let zeroBuffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())
        let platform = AVAudioEngineMicrophonePlatform(
            startupReadinessTimeout: 0,
            engineStarter: { _, _, _, tapHandler in
                tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 1))
            }
        )

        XCTAssertThrowsError(
            try platform.configureAndStart(
                vpioEnabled: false,
                bufferSize: 256,
                tapHandler: { _, _ in }
            )
        ) { error in
            XCTAssertEqual(
                error as? AVAudioEngineMicrophonePlatformError,
                .initialReadinessTimedOut
            )
        }
        XCTAssertFalse(platform.isEngineRunning)
    }

    func testBluetoothVPIOReferenceOnlyPreferredRouteFallsBack() throws {
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let deliveredBufferCount = OSAllocatedUnfairLock(initialState: 0)
        let referenceOnlyBuffer = UncheckedSendableAudioPCMBuffer(
            makeStartupReadinessBuffer(channels: 2)
        )
        referenceOnlyBuffer.buffer.floatChannelData?[1][0] = 0.001
        let microphoneBuffer = UncheckedSendableAudioPCMBuffer(
            makeStartupReadinessBuffer(nonZero: true)
        )
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    MeetingInputDeviceAttempt(
                        source: .selected(uid: "bluetooth"),
                        deviceID: 10
                    ),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { $0 == 10 },
            engineStarter: { _, _, _, tapHandler in
                let invocation = invocationCount.withLock { value -> Int in
                    value += 1
                    return value
                }
                let buffer = invocation <= 2 ? referenceOnlyBuffer : microphoneBuffer
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: true,
            bufferSize: 256,
            tapHandler: { _, _ in
                deliveredBufferCount.withLock { $0 += 1 }
            }
        )

        XCTAssertEqual(invocationCount.withLock { $0 }, 3)
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)
        )
        XCTAssertEqual(
            deliveredBufferCount.withLock { $0 },
            1,
            "VPIO reference audio must not hide a silent Bluetooth microphone channel"
        )
    }

    func testUnresolvedSystemDefaultZeroFilledRouteFallsBack() throws {
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let deliveredBufferCount = OSAllocatedUnfairLock(initialState: 0)
        let zeroBuffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    .implicitSystemDefault(resolvedDeviceID: nil),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { _, _, _, tapHandler in
                invocationCount.withLock { $0 += 1 }
                tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in
                deliveredBufferCount.withLock { $0 += 1 }
            }
        )

        XCTAssertEqual(invocationCount.withLock { $0 }, 3)
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)
        )
        XCTAssertEqual(
            deliveredBufferCount.withLock { $0 },
            1,
            "Unresolved topology must fail closed until Core Audio identifies the route"
        )
    }

    func testNonBluetoothZeroFilledBufferCountsAsReady() throws {
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let zeroBuffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { _, _, _, tapHandler in
                invocationCount.withLock { $0 += 1 }
                tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        XCTAssertTrue(platform.isEngineRunning)
        XCTAssertEqual(invocationCount.withLock { $0 }, 1)
    }

    func testPreparedStartFallsBackWhenConfigurationChangesDuringReadiness() throws {
        let preparedEngine = OSAllocatedUnfairLock<AVAudioEngine?>(initialState: nil)
        let postedConfigurationChange = OSAllocatedUnfairLock(initialState: false)
        let startedEngines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { engine, _, _, tapHandler in
                startedEngines.withLock { $0.append(engine) }
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                let shouldPost = postedConfigurationChange.withLock { posted -> Bool in
                    guard !posted else { return false }
                    posted = true
                    return true
                }
                if shouldPost, let engine = preparedEngine.withLock({ $0 }) {
                    NotificationCenter.default.post(
                        name: .AVAudioEngineConfigurationChange,
                        object: engine
                    )
                }
            }
        )
        defer { platform.stopEngine() }

        platform.prepare(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )
        let preparedState = platform.preparedEngineStateForTesting
        XCTAssertTrue(preparedState.prepared)
        preparedEngine.withLock { $0 = preparedState.engine }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        let engines = startedEngines.withLock { $0 }
        XCTAssertEqual(engines.count, 2, "stale prepared start + cold fallback")
        XCTAssertTrue(engines[0] === preparedState.engine)
        XCTAssertFalse(engines[0] === engines[1])
        XCTAssertTrue(platform.isEngineRunning)
    }

    func testBluetoothProfileChangeBeforeUsableBufferDoesNotInvalidateStartup() throws {
        let buffer = UncheckedSendableAudioPCMBuffer(
            makeStartupReadinessBuffer(nonZero: true)
        )
        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [.implicitSystemDefault(resolvedDeviceID: 10)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { $0 == 10 },
            engineStarter: { engine, _, _, tapHandler in
                NotificationCenter.default.post(
                    name: .AVAudioEngineConfigurationChange,
                    object: engine
                )
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        XCTAssertNoThrow(
            try platform.configureAndStart(
                vpioEnabled: false,
                bufferSize: 256,
                tapHandler: { _, _ in }
            ),
            "A usable buffer from the post-change AirPods graph should certify startup"
        )
    }

    func testColdStartFallsBackWhenConfigurationChangesDuringReadiness() throws {
        let currentEngine = OSAllocatedUnfairLock<AVAudioEngine?>(initialState: nil)
        let currentDefaultDeviceID = OSAllocatedUnfairLock<AudioDeviceID>(initialState: 10)
        let postedConfigurationChange = OSAllocatedUnfairLock(initialState: false)
        let startedEngines = OSAllocatedUnfairLock(initialState: [AVAudioEngine]())
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    .implicitSystemDefault(
                        resolvedDeviceID: currentDefaultDeviceID.withLock { $0 }
                    ),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20),
                ]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { engine, _, _, tapHandler in
                currentEngine.withLock { $0 = engine }
                startedEngines.withLock { $0.append(engine) }
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                let shouldPost = postedConfigurationChange.withLock { posted -> Bool in
                    guard !posted else { return false }
                    posted = true
                    return true
                }
                if shouldPost, let engine = currentEngine.withLock({ $0 }) {
                    currentDefaultDeviceID.withLock { $0 = 11 }
                    NotificationCenter.default.post(
                        name: .AVAudioEngineConfigurationChange,
                        object: engine
                    )
                }
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        let engines = startedEngines.withLock { $0 }
        XCTAssertEqual(engines.count, 2, "stale cold start + next route")
        XCTAssertFalse(engines[0] === engines[1])
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)
        )
        XCTAssertTrue(platform.isEngineRunning)
    }

    func testImplicitDefaultFallsBackWhenDefaultChangesDuringReadiness() throws {
        let platformBox = OSAllocatedUnfairLock<AVAudioEngineMicrophonePlatform?>(initialState: nil)
        let changedDefault = OSAllocatedUnfairLock(initialState: false)
        let startedDeviceIDs = OSAllocatedUnfairLock(initialState: [AudioDeviceID?]())
        let currentDeviceID = OSAllocatedUnfairLock<AudioDeviceID?>(initialState: nil)
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [
                    .implicitSystemDefault(resolvedDeviceID: 10),
                    MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20),
                ]
            },
            inputDeviceSetter: { deviceID, _ in
                currentDeviceID.withLock { $0 = deviceID }
                return true
            },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { _, _, _, tapHandler in
                startedDeviceIDs.withLock { $0.append(currentDeviceID.withLock { $0 }) }
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                let shouldChange = changedDefault.withLock { changed -> Bool in
                    guard !changed else { return false }
                    changed = true
                    return true
                }
                if shouldChange {
                    platformBox.withLock { $0 }?.noteDefaultInputChangeForTesting()
                }
            }
        )
        platformBox.withLock { $0 = platform }
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        XCTAssertEqual(startedDeviceIDs.withLock { $0 }, [nil, 20])
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 20)
        )
    }

    func testExplicitSelectedStartIgnoresUnrelatedDefaultChangeDuringReadiness() throws {
        let platformBox = OSAllocatedUnfairLock<AVAudioEngineMicrophonePlatform?>(initialState: nil)
        let invocationCount = OSAllocatedUnfairLock(initialState: 0)
        let buffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer(nonZero: true))

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [MeetingInputDeviceAttempt(source: .selected(uid: "usb"), deviceID: 10)]
            },
            inputDeviceSetter: { _, _ in true },
            startupReadinessTimeout: 0,
            bluetoothInputState: { _ in false },
            engineStarter: { _, _, _, tapHandler in
                invocationCount.withLock { $0 += 1 }
                tapHandler(buffer.buffer, AVAudioTime(hostTime: 1))
                platformBox.withLock { $0 }?.noteDefaultInputChangeForTesting()
            }
        )
        platformBox.withLock { $0 = platform }
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in }
        )

        XCTAssertEqual(invocationCount.withLock { $0 }, 1)
        XCTAssertEqual(
            platform.lastSucceededAttempt,
            MeetingInputDeviceAttempt(source: .selected(uid: "usb"), deviceID: 10)
        )
    }

    func testImplicitDefaultRefreshesBluetoothSignalPolicyWhileRunning() throws {
        let currentDeviceID = OSAllocatedUnfairLock<AudioDeviceID>(initialState: 20)
        let currentBluetoothState = OSAllocatedUnfairLock<Bool?>(initialState: false)
        let installedTapHandler = OSAllocatedUnfairLock<
            (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
        >(initialState: nil)
        let deliveredBufferCount = OSAllocatedUnfairLock(initialState: 0)
        let zeroBuffer = UncheckedSendableAudioPCMBuffer(makeStartupReadinessBuffer())
        let signalBuffer = UncheckedSendableAudioPCMBuffer(
            makeStartupReadinessBuffer(nonZero: true)
        )

        let platform = AVAudioEngineMicrophonePlatform(
            deviceAttemptsBuilder: {
                [.implicitSystemDefault(resolvedDeviceID: currentDeviceID.withLock { $0 })]
            },
            startupReadinessTimeout: 0,
            bluetoothInputState: { deviceID in
                deviceID == 10 ? currentBluetoothState.withLock { $0 } : false
            },
            engineStarter: { _, _, _, tapHandler in
                installedTapHandler.withLock { $0 = tapHandler }
                tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 1))
            }
        )
        defer { platform.stopEngine() }

        try platform.configureAndStart(
            vpioEnabled: false,
            bufferSize: 256,
            tapHandler: { _, _ in
                deliveredBufferCount.withLock { $0 += 1 }
            }
        )
        XCTAssertEqual(deliveredBufferCount.withLock { $0 }, 1)

        currentDeviceID.withLock { $0 = 10 }
        currentBluetoothState.withLock { $0 = nil }
        platform.refreshActiveTapSignalPolicyForTesting()
        let tapHandler = try XCTUnwrap(installedTapHandler.withLock { $0 })
        tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 2))

        currentBluetoothState.withLock { $0 = true }
        platform.refreshActiveTapSignalPolicyForTesting()
        tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 3))

        currentBluetoothState.withLock { $0 = nil }
        platform.refreshActiveTapSignalPolicyForTesting()
        tapHandler(zeroBuffer.buffer, AVAudioTime(hostTime: 4))

        currentBluetoothState.withLock { $0 = true }
        platform.refreshActiveTapSignalPolicyForTesting()
        tapHandler(signalBuffer.buffer, AVAudioTime(hostTime: 5))

        XCTAssertEqual(
            deliveredBufferCount.withLock { $0 },
            2,
            "Unresolved/Bluetooth transitions must filter zero PCM but forward real samples"
        )
    }
}

private func makeStartupReadinessBuffer(
    nonZero: Bool = false,
    channels: AVAudioChannelCount = 1
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
    buffer.frameLength = 32
    if nonZero {
        buffer.floatChannelData?[0][0] = 0.001
    }
    return buffer
}

private final class WeakReadinessEngine: @unchecked Sendable {
    weak var engine: AVAudioEngine?

    init(_ engine: AVAudioEngine) {
        self.engine = engine
    }
}
