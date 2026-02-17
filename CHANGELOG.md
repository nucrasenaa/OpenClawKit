# Changelog

## 2026.1.2 - 2026-02-17

### Added

- GitHub Actions CI/CD foundation with `ci.yml`, `security.yml`, and tag-driven
  `release.yml` workflows for build/test/security/release automation.
- Telegram channel adapter with polling lifecycle, mention gating, typing signal,
  outbound delivery, and deterministic transport-mocked tests.
- WhatsApp Cloud API adapter with send endpoint integration, webhook verification
  + event ingestion support, and deterministic transport-mocked tests.
- Model-provider expansion with OpenAI-compatible, Anthropic, and Gemini
  providers plus expanded provider configuration blocks.
- iOS deploy-time provider/model selection and persisted credentials for OpenAI,
  OpenAI-compatible, Anthropic, Gemini, and Foundation provider modes.
- Weather skill example at `skills/weather` using free Open-Meteo APIs and a
  no-dependency Python script entrypoint.
- Multi-agent-lite config and routing with named agent IDs and route maps
  (`channel[:account[:peer]] -> agent`) plus iOS agent routing controls.
- Structured channel diagnostics events for ingress/routing/model-call/egress
  phases to improve runtime observability.

### Changed

- `OpenClawConfig` is now default-decode resilient across top-level, channel,
  model, and agent sections for backward-compatible config evolution.
- Session resolution now updates stored agent binding when route mapping changes,
  enabling lightweight per-route agent assignment.
- Conversation memory prompt formatting now uses explicit trust boundaries and
  escapes unsafe markup tokens before injection into model prompts.
- Skill registry prompt snapshots now surface script entrypoint hints and
  enforce safe entrypoint resolution within each skill directory.

### Tests

- Expanded adapter coverage with Telegram and WhatsApp adapter suites plus
  additional channel registry dispatch E2E tests.
- Expanded model routing coverage for OpenAI-compatible, Anthropic, Gemini, and
  metadata fallback provider behavior.
- Added iOS build-gate-compatible tests for multi-agent route mapping and
  auto-reply mapped-agent session binding.
- Added skill runtime tests for script-file execution, HTTP helper guards, and
  skill entrypoint traversal prevention.
- Added conversation memory hardening tests for escaping and context-boundary
  formatting.

## 2026.1.1.1 - 2026-02-15

### Fixed

- Discord deploy lifecycle now starts a gateway presence client so deployed bots
  report online status and shut down presence cleanly when deployment stops.
- Discord message handling now uses mention-only trigger policy with startup
  backlog cursor initialization to prevent replay spam on deploy.
- Discord mention triggers now acknowledge with an 👀 reaction before reply
  processing begins.
- Adapter conversation turns are now persisted in a file-backed conversation
  memory store and reinjected into subsequent prompts for session-aware context.

### Tests

- Expanded Discord adapter coverage for presence lifecycle startup/teardown,
  backlog skip behavior, mention-only filtering, and reaction acknowledgement.
- Added conversation memory store persistence/context formatting tests and
  auto-reply integration tests for prompt context injection.

## 2026.1.1 - 2026-02-15

### Added

- Model-provider routing module (`OpenClawModels`) with configurable provider
  selection, fallback behavior, and runtime integration through
  `EmbeddedAgentRuntime`.
- Apple Foundation Models provider behind compile/runtime availability guards
  and deterministic fallback tests for unsupported platforms.
- Local-model adapter contracts inspired by on-device lifecycle patterns,
  including load/unload semantics and streaming-friendly generation hooks.
- Workspace skill system (`OpenClawSkills`) with `SKILL.md` discovery,
  frontmatter parsing, precedence-aware merging, and runtime prompt injection.
- JavaScriptCore skill execution sandbox with strict workspace path jail and
  guarded filesystem host APIs for code-executing skills on Apple platforms.
- Bootstrap/personality prompt context loading (`AGENTS.md`, `SOUL.md`,
  `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`,
  `MEMORY.md`) integrated into prompt assembly.
- Live Discord channel adapter with deploy/stop lifecycle controls, inbound
  polling, outbound delivery, auth-safe error handling, and route-aware message
  envelopes.
- iOS example app expanded into Deploy/Chat tabs with `TabView`, local
  transcript persistence, periodic memory summarization jobs, and runtime
  deployment wiring for local + Discord chat flows.

### Changed

- iOS example project now links the local `OpenClawKit` package product and
  enforces warnings-as-errors from project build settings.
- iOS compatibility hardened in core utilities (home-directory resolution and
  process execution fallback behavior).
- iOS validation scripts now rely on target build settings for warnings-as-
  errors to avoid transitive package flag conflicts.

### Documentation

- Added inline `///` API documentation for major public surfaces in
  `OpenClawKit`, `OpenClawAgents`, `OpenClawChannels`, and `OpenClawCore`
  configuration models.

## 2026.1.0 - 2026-02-15

### Added

- Multi-target Swift 6.2 package architecture with strict-concurrency settings and
  library products for protocol, core, gateway, agents, plugins, channels, memory,
  media, and top-level SDK access.
- Cross-platform compatibility shims for crypto, networking, security, process
  execution, and filesystem APIs, including Linux fallbacks.
- Schema-driven gateway protocol generation (`Scripts/protocol-gen-swift.mjs`) and
  generated `OpenClawProtocol` models with `AnyCodable` support.
- Actor-isolated gateway transport with reconnect backoff, request/response tracking,
  TLS fingerprint validation, and tick watchdog handling.
- Config/session persistence stack with cached config loading, session routing helpers,
  session key resolution, and file-backed session store.
- Embedded agent runtime with tool orchestration, lifecycle events, and timeout-aware
  execution semantics.
- Static Swift plugin system with hook dispatch, custom gateway methods, and service
  lifecycle management.
- Channel abstractions and auto-reply engine with in-memory adapter support and
  session-aware reply routing.
- Runtime subsystem primitives for memory indexing/search, media normalization,
  hook registry, cron scheduling, and pairing/approval security state.
- High-level `OpenClawSDK` facade APIs for configuration/session operations, command
  execution, environment checks, and reply flow composition.
- Unit and E2E Swift Testing suites covering protocol models, platform shims,
  gateway transport, runtime subsystems, channels, plugins, and SDK facade behavior.
- Strict networking concurrency validation script:
  `Scripts/check-networking-concurrency.sh`.
- Project documentation set: comprehensive `README.md`, architecture guide,
  testing guide, API surface reference, and MIT `LICENSE`.

