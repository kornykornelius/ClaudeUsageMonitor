#!/bin/bash
#
# Runs the correctness checks in Tools/checks against the app's real sources.
#
# There is no Xcode test target on purpose: this is a single-window menu bar
# utility, and a target plus scheme plus host application is more machinery
# than the problem needs. What the app does need is a way to exercise the
# parts that are awkward to reach by hand — Cloudflare challenge detection,
# the percentage conversion, backoff arithmetic, and the shape of claude.ai's
# error bodies. That is what this script does, in about two seconds.
#
#     ./Tools/run-checks.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# Only the model and service layers: the checks are all pure logic, and
# pulling in the views would drag in SwiftUI for no benefit.
cp "$ROOT"/ClaudeUsageMonitor/Models/*.swift "$BUILD/"
cp "$ROOT"/ClaudeUsageMonitor/Services/*.swift "$BUILD/"
cp "$ROOT"/Tools/checks/main.swift "$BUILD/"

# UsageSnapshot+Samples pulls in nothing extra, but the view-only sample data
# is not needed here and its absence keeps the compile quick.
rm -f "$BUILD/UsageSnapshot+Samples.swift"

swiftc -swift-version 5 \
       -target arm64-apple-macos14.0 \
       -o "$BUILD/checks" \
       "$BUILD"/*.swift

"$BUILD/checks" "$ROOT/Tools/fixtures/cloudflare-challenge.html"
