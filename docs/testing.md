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

## 2026.1.4 Reliability + Security Coverage Highlights

- Runtime streaming coverage for chunked generation and final-marker behavior.
- Channel auto-reply coverage for stream-path execution and typing heartbeat stop conditions.
- Credential-store coverage for keychain/file backends plus legacy plaintext secret migration.
- Security-audit coverage for risky defaults, plaintext secret detection, permission checks, and diagnostics emission.
- Throttling coverage across channel outbound delivery and provider routing (`delay` and `drop` strategies).
