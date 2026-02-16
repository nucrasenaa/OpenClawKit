#!/usr/bin/env bash
set -euo pipefail

PROJECT="Examples/iOS/OpenClawiOS/OpenClawiOS.xcodeproj"
SCHEME="OpenClawiOS"
DESTINATION="generic/platform=iOS Simulator"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  CLANG_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build
