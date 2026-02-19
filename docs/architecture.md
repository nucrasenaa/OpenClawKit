# OpenClawKit Architecture

This package is organized into layered SwiftPM targets so core concerns remain isolated
while exposing a simple top-level facade.

## Layer Overview

1. `OpenClawProtocol`
   - Transport models (`RequestFrame`, `ResponseFrame`, `EventFrame`, `GatewayFrame`)
   - Protocol version and error code constants
   - Generated from `Scripts/protocol-schema.json`

2. `OpenClawCore`
   - Cross-platform shims (crypto/network/security/process/fs)
   - Config and session persistence
   - Cron, hooks, and security runtime state
   - Diagnostics and usage aggregation (`RuntimeDiagnosticsPipeline`)

3. `OpenClawGateway`
   - Actor-safe transport client
   - Socket abstraction (`GatewaySocket`)
   - Reconnect/watchdog and pending-request lifecycle

4. `OpenClawAgents`
   - Tool registry and runtime lifecycle events
   - Timeout-aware run execution and orchestration
   - Structured runtime diagnostics emission (`run.*`, `model.call.*`)

5. `OpenClawPlugins`
   - Static plugin API (Swift protocols, no runtime JS loading)
   - Hook dispatch, custom gateway methods, service lifecycle

6. `OpenClawChannels`
   - Channel adapters and outbound routing
   - Auto-reply engine integrating sessions + runtime execution
   - Delivery health snapshots, retry/backoff policy, and command handlers

7. `OpenClawMemory` and `OpenClawMedia`
   - Memory indexing/search primitives
   - Media normalization, MIME classification, and limits

8. `OpenClawKit`
   - Facade API (`OpenClawSDK`) exposing primary integration points
   - Re-exports lower-level modules for advanced use

## Concurrency Model

- Mutable runtime state is actor-isolated.
- Public model types are `Sendable`.
- Cross-task callbacks are `@Sendable`.
- Networking safety is validated by `Scripts/check-networking-concurrency.sh`.

## Observability Flow

`AutoReplyEngine` and `EmbeddedAgentRuntime` emit `RuntimeDiagnosticEvent` payloads
into an injected `RuntimeDiagnosticSink`. Host apps can plug a
`RuntimeDiagnosticsPipeline` sink to:

- retain recent event timelines (`recentEvents(limit:)`)
- inspect aggregate usage (`usageSnapshot()`)
- power app-level diagnostics surfaces (for example, the expanded iOS sample tabs)

## Feature Implementation Guidance

When adding new features:

- add protocol surface in `OpenClawProtocol` first (if needed)
- add core/runtime capability in the appropriate module target
- wire facade entry points in `OpenClawSDK` only after lower layers are tested
- add unit + E2E coverage with Swift Testing
