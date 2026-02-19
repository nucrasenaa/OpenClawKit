# Testing Guide

OpenClawKit uses Swift Testing (`import Testing`) for both unit and E2E coverage.

## Run All Tests

```bash
swift test
```

## Test Structure

- `Tests/OpenClawKitTests`
  - unit-level tests for protocol, core shims, runtime primitives, diagnostics, facade helpers
- `Tests/OpenClawKitE2ETests`
  - end-to-end tests across transport/runtime/channels/plugin flow and reconnect lifecycle

## Networking Concurrency Gate

Run this before committing networking changes:

```bash
Scripts/check-networking-concurrency.sh
```

This enforces strict concurrency diagnostics for networking-related targets.

## API Key Dependent E2E Workflows

Some integration-style E2E workflows may require provider keys:

- `OPENAI_API_KEY`
- `GEMINI_API_KEY`

Set these in local `.env` (ignored by git) when running provider-backed E2E scenarios.
Never commit `.env`.

## Recommended Local Validation Sequence

1. `swift build`
2. `Scripts/check-networking-concurrency.sh`
3. `swift test`
4. `./Scripts/build-ios-example.sh`

## 2026.1.3 Reliability Coverage Highlights

- Runtime diagnostics coverage for successful and timeout-failure run paths.
- Channel auto-reply coverage for outbound delivery failures and emitted diagnostics metadata.
- Gateway transport E2E coverage that asserts reconnect attempts stop after explicit disconnect.
