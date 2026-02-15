# Testing Guide

OpenClawKit uses Swift Testing (`import Testing`) for both unit and E2E coverage.

## Run All Tests

```bash
swift test
```

## Test Structure

- `Tests/OpenClawKitTests`
  - unit-level tests for protocol, core shims, runtime primitives, facade helpers
- `Tests/OpenClawKitE2ETests`
  - end-to-end tests across transport/runtime/channels/plugin flow

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
