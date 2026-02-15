# OpenClawKit

Swift package SDK for running local OpenClaw-compatible AI agent workflows in native apps.

## Status

This repository is under active porting from `.cursor/openclaw` TypeScript sources into a
multi-target Swift 6.2 package with Apple and Linux compatibility.

## Modules

- `OpenClawProtocol`
- `OpenClawCore`
- `OpenClawGateway`
- `OpenClawAgents`
- `OpenClawPlugins`
- `OpenClawChannels`
- `OpenClawMemory`
- `OpenClawMedia`
- `OpenClawKit`

## Protocol model generation

Gateway protocol models are generated from `Scripts/protocol-schema.json`.

```bash
node Scripts/protocol-gen-swift.mjs
```

