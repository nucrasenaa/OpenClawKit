# OpenClawSDK API Surface

`OpenClawSDK` provides high-level app entry points that compose lower-level modules.

## Configuration and Session Storage

- `loadConfig(from:cacheTTLms:)`
- `saveConfig(_:to:)`
- `loadSessionStore(from:)`
- `saveSessionStore(_:)`
- `resolveSessionKey(explicit:context:config:)`

## Runtime and Execution

- `runExec(_:cwd:)`
- `runCommandWithTimeout(_:timeoutMs:cwd:)`
- `waitForever()`

## Environment and System

- `ensurePortAvailable(_:)`
- `ensureBinary(_:)`

## Channel and Reply Flows

- `monitorWebChannel(config:sessionStoreURL:diagnosticsPipeline:)`
- `getReplyFromConfig(config:sessionStoreURL:inbound:diagnosticsPipeline:)`

## Observability Helpers

- `makeDiagnosticsPipeline(eventLimit:)`

## Related Supporting Types

- `OpenClawConfig`
- `SessionStore`
- `InboundMessage`
- `OutboundMessage`
- `RuntimeDiagnosticsPipeline`
- `RuntimeDiagnosticEvent`
- `RuntimeUsageSnapshot`
- `PortInUseError`
- `ProcessResult`
