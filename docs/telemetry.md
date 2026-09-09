# Local telemetry log

MacParakeet writes every emitted `TelemetryEventSpec` to:

```text
~/Library/Logs/MacParakeet/telemetry.jsonl
```

Each line is one encoded `TelemetryEvent` JSON object. It contains the event
name, event properties, app and OS versions, locale, chip type, a random
process-session ID, the `gui` or `cli` surface, and a timestamp.

The GUI and CLI use `LoggerTelemetryService`. The service has no network
transport, and MacParakeet does not upload this file automatically.

`CrashReporter` separately writes local crash reports to
`~/Library/Application Support/MacParakeet/crash_report.txt`.
