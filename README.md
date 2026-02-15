# OpenClawKit

`OpenClawKit` is a Swift package SDK for running local OpenClaw-style AI agent workflows
inside native Swift applications.

It follows Swift ecosystem conventions:

- Swift 6.2 strict-concurrency oriented design (`actor`, `Sendable`, async APIs)
- multi-target package architecture for protocol/core/runtime/channel/plugin concerns
- Apple platform support with Linux compatibility fallbacks
- Swift Testing-first unit and E2E test coverage

## What You Get

- **Gateway transport layer** with actor-isolated request lifecycle, reconnect logic,
  and TLS fingerprint validation
- **Agent runtime** with tool orchestration, timeout handling, and lifecycle events
- **Static plugin system** with hook dispatch, gateway method registration, and service lifecycle
- **Channel and auto-reply core** with typed channel IDs and session-aware reply routing
- **Runtime primitives** for memory indexing/search, media classification/limits, hook registry,
  cron scheduling, and security pairing/approval state
- **Facade API** in `OpenClawSDK` for app-level integration

## Package Modules

- `OpenClawProtocol` - generated protocol models and frame types
- `OpenClawCore` - config/session stores, platform shims, security/cron/hooks utilities
- `OpenClawGateway` - networking transport, socket abstraction, reconnect/watchdog logic
- `OpenClawAgents` - run lifecycle, tool registry, timeout-aware execution
- `OpenClawPlugins` - static plugin API, hooks, services, custom method registration
- `OpenClawChannels` - channel adapters plus auto-reply engine core
- `OpenClawMemory` - memory documents and local search model
- `OpenClawMedia` - media normalization and MIME-kind handling
- `OpenClawKit` - top-level facade and re-export surface

## Platform and Compatibility

OpenClawKit targets Apple platforms and is structured to run on Linux with fallbacks:

- `CryptoKit` where available, with `swift-crypto` (`Crypto`) fallback
- `FoundationNetworking` conditional imports for Linux networking support
- security abstractions for platforms where native security APIs differ

For networking safety, a strict-concurrency compile gate is included:

```bash
Scripts/check-networking-concurrency.sh
```

## Installation

Add OpenClawKit as a SwiftPM dependency:

```swift
.package(url: "https://github.com/MarcoDotIO/OpenClawKit.git", branch: "main")
```

Then depend on the product in your target:

```swift
.product(name: "OpenClawKit", package: "OpenClawKit")
```

## Quick Start

```swift
import OpenClawKit

let sdk = OpenClawSDK.shared
let config = OpenClawConfig()
let sessionsURL = URL(fileURLWithPath: "./state/sessions.json")

let outbound = try await sdk.getReplyFromConfig(
    config: config,
    sessionStoreURL: sessionsURL,
    inbound: InboundMessage(channel: .webchat, peerID: "user-1", text: "Hello")
)

print(outbound.text)
```

## Testing

Run full unit + E2E suite:

```bash
swift test
```

For features that integrate with hosted model providers, set API keys in a local `.env`
file (already ignored by `.gitignore` in this repository):

- `OPENAI_API_KEY`
- `GEMINI_API_KEY`

Do not commit `.env` values.

## Development Docs

- Architecture notes: `docs/architecture.md`
- Testing guide: `docs/testing.md`
- SDK API surface: `docs/api-surface.md`

Protocol model generation is schema-driven:

```bash
node Scripts/protocol-gen-swift.mjs
```

## Acknowledgements

This project is a Swift-native SDK inspired by and aligned with the architecture and
protocol design from the broader OpenClaw ecosystem.

Huge credit to the OpenClaw maintainers and contributors for the upstream system design,
feature set, and ongoing innovation in local agent runtime tooling.

Upstream project:

- https://github.com/openclaw/openclaw

## License

OpenClawKit is released under the MIT License. See `LICENSE`.

