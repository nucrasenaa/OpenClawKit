#!/usr/bin/env bash
set -euo pipefail

swift build \
  --target OpenClawCore \
  --target OpenClawGateway \
  --target OpenClawKit \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors

