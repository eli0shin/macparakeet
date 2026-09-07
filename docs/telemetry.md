# Telemetry and crash-report privacy

MacParakeet fork builds do not collect or upload usage analytics, CLI operation
data, or crash reports.

The fork has no telemetry event catalog, send call sites, service abstraction,
HTTP transport, or telemetry endpoint. Environment variables and persisted
defaults cannot enable delivery.

`CrashReporter` can write a local report to
`~/Library/Application Support/MacParakeet/crash_report.txt`. The app does not
upload or automatically delete this file. It stays on the Mac for
user-requested diagnosis.

Feedback is separate from telemetry. A feedback request is sent only after an
explicit user action and keeps its existing attachment controls. MacParakeet
does not silently attach the local crash report or diagnostic logs.

Local `os.Logger` output and audio diagnostic logs are not network telemetry.
They remain available when a user chooses to supply diagnostics.

The removed upstream Cloudflare Worker and D1 design is recorded as historical
context in [ADR-012](../spec/adr/012-telemetry-system.md). It is not part of this
fork's current architecture.
