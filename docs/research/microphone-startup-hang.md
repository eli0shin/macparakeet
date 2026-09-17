# Microphone startup hang

Investigation date: 2026-09-17.

## Evidence and limits

The [work-computer report](https://artifacts.home.arpa/macparakeet-bt-mic-hang-report/README.md)
and its [September 17 log](https://artifacts.home.arpa/macparakeet-bt-mic-hang-report/logs/episode-2026-09-17.log)
show a Bluetooth readiness timeout, built-in fallback errors with `-10868`,
and later dictation attempts waiting until the user cancels. The Bluetooth
failure at 14:57:20.714 is followed by the built-in failure at 15:11:41.918:
861.204 seconds later. The latter reports only 102.786 ms for device selection.
The long interval is therefore not explained by that measured setter call.

The [September 11 log](https://artifacts.home.arpa/macparakeet-bt-mic-hang-report/logs/episode-2026-09-11.log)
shows delayed fallback results near route changes. The
[September 16 log](https://artifacts.home.arpa/macparakeet-bt-mic-hang-report/logs/episode-2026-09-16.log)
shows successful Bluetooth capture after an app relaunch. These observations
do not identify the exact framework call that blocked.

The affected source at commit `deb7eedcd1d6` already replaced `AVAudioEngine`
after startup errors. Its `blocks_vpio_promotion` log field describes the
subscription request, not a retained failure flag. See
[`MicrophoneEnginePlatform.swift`](../../Sources/MacParakeetCore/Audio/MicrophoneEnginePlatform.swift)
and [`SharedMicrophoneStream.swift`](../../Sources/MacParakeetCore/Audio/SharedMicrophoneStream.swift).

## Confirmed defect: replaced engines remain alive

The configuration observer captured `UncheckedSendableAudioEngine` in a block
queued on the platform queue. That wrapper strongly owns its engine. The same
queue executes the complete fallback chain, so the queued block kept the failed
engine alive while the next engine started. Notification-driven recovery also
kept its old engine reference for the entire restart.

Regression tests use weak engine references, not arrays that retain engines:

```sh
swift test --filter 'MicrophoneEnginePlatformStartupReadinessTests/test(FailedEngineIsReleased|ConfigurationRecoveryReleases)'
```

Before the fix, the control without a notification passed. Both notification
cases failed because the retired engine was still alive at replacement startup.
After replacing the strong capture with an engine UUID, all three tests passed.
Queued events now check that UUID before accessing the current engine. They do
not retain a retired engine across fallback or recovery.

Source and tests:
[`installConfigurationChangeObserverLocked`](../../Sources/MacParakeetCore/Audio/MicrophoneEnginePlatform.swift),
[`MicrophoneEnginePlatformStartupReadinessTests.swift`](../../Tests/MacParakeetTests/Audio/MicrophoneEnginePlatformStartupReadinessTests.swift).

This proves the engine-lifetime defect and its repair. It does not prove that
this defect accounts for every hardware stall in the report. The local test
computer has only built-in audio devices, not the reported Bose headset.

## Confirmed dependency: meeting tap waits on the platform queue

`MicrophoneCapture` read the platform's `inputFormat` for first-buffer logging.
That accessor synchronously waits on the platform queue. It ran inside the tap,
including while the platform was still starting the engine. A cleanup operation
that waits for that callback can therefore encounter a circular dependency.

The regression test `testEarlyFirstBufferDoesNotReadPlatformFormat` failed
before the fix. First-buffer diagnostics now use `buffer.format` and asynchronous
file logging. They no longer query the engine from that callback.

Source and test:
[`MicrophoneCapture.swift`](../../Sources/MacParakeetCore/Audio/MicrophoneCapture.swift),
[`MicrophoneCaptureTests.swift`](../../Tests/MacParakeetTests/Audio/MicrophoneCaptureTests.swift).

## Format hypothesis not yet established

Apple documents that a hardware-backed input node does not convert formats:
its output format must match its hardware input format. Apple also documents
that a non-nil tap format attempts to set the node's output bus format. See the
SDK headers `AVFAudio.framework/Headers/AVAudioIONode.h` (`AVAudioInputNode`
discussion) and `AVAudioNode.h` (`installTapOnBus:bufferSize:format:block:`), and
the [input-node documentation](https://developer.apple.com/documentation/avfaudio/avaudioinputnode).

The application changes an explicit device through the input AudioUnit, then
checks the node output format and installs a nil-format tap. The report does not
contain both hardware and node-output formats for the failing attempt. A bus
format mismatch is plausible, but changing engine-owned AudioUnit formats or
claiming an exact mismatch from these logs alone is not justified.

## Recovery policy and diagnostics

- A one-second first-buffer timeout replaces the engine and retries the same
  route before fallback. A prepared timeout consumes that route's first attempt.
- Retry budgets are local to a start. Tests verify a fresh subscription after
  exhausted readiness attempts and after `-10868`.
- `shared_mic_operation_begin`, `_end`, and `_stalled` events identify operations,
  engine UUIDs, route sources, and elapsed time. Subscription events also carry
  a subscription UUID. Queue waits are recorded separately from engine work.
- The operation watchdog runs on an independent queue. It logs a call still
  pending after two seconds without reading the engine or waiting on its queue.
  It does not cancel a blocked framework call.

[`MicrophoneOperationDiagnosticsTests.swift`](../../Tests/MacParakeetTests/Audio/MicrophoneOperationDiagnosticsTests.swift)
blocks the injected engine start and verifies that the watchdog reports it
before release. It also checks queued subscriptions and suppression of stale
watchdog events after completion.

No app restart or helper process is part of these changes. Recovery from an
arbitrary permanently blocked framework call is not established by these tests.
