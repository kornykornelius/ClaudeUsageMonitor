#!/bin/bash
#
# Renders every popover state to a PNG so the UI can be reviewed without
# clicking through it — several states (Cloudflare challenging you, a plan
# that reports no Opus quota, an account with no quota data at all) are close
# to impossible to reach on demand against a live account.
#
#     ./Tools/render-snapshots.sh [output-directory]
#
# Defaults to ./build/snapshots, which is gitignored.
#
# Note: ImageRenderer does not draw TextField, SecureField or ProgressView —
# they appear as yellow placeholders. That is a limitation of offscreen
# rendering, not of the app. It is also why the utilisation bar is drawn from
# primitives rather than with ProgressView.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/snapshots}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

mkdir -p "$OUT"

cp "$ROOT"/ClaudeUsageMonitor/Models/*.swift "$BUILD/"
cp "$ROOT"/ClaudeUsageMonitor/Services/*.swift "$BUILD/"
cp "$ROOT"/ClaudeUsageMonitor/ViewModels/*.swift "$BUILD/"
cp "$ROOT"/ClaudeUsageMonitor/Views/*.swift "$BUILD/"
cp "$ROOT"/Tools/snapshots/main.swift "$BUILD/"

# ClaudeUsageMonitorApp.swift is deliberately not copied: it carries @main,
# which would collide with main.swift.

# The #Preview macros need the previews toolchain, which a plain swiftc
# invocation does not provide. They are not needed to render.
python3 - "$BUILD/PopoverView.swift" <<'PY'
import sys
path = sys.argv[1]
source = open(path).read()
marker = "// MARK: - Previews"
if marker in source:
    open(path, "w").write(source[:source.index(marker)])
PY

swiftc -swift-version 5 \
       -target arm64-apple-macos14.0 \
       -o "$BUILD/snapshots" \
       "$BUILD"/*.swift

"$BUILD/snapshots" "$OUT"
echo ""
echo "Snapshots written to $OUT"
