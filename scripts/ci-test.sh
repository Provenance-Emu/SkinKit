#!/usr/bin/env bash
# Build and test SkinKit on an iOS or tvOS simulator.
# Usage: scripts/ci-test.sh ios|tvos
# Picks the first available iPhone / Apple TV simulator, so it works across
# Xcode versions without hard-coding device names.
set -euo pipefail

platform="${1:?usage: ci-test.sh ios|tvos}"
case "$platform" in
  ios)  runtime="iOS";  family="iPhone" ;;
  tvos) runtime="tvOS"; family="Apple TV" ;;
  *) echo "unknown platform: $platform" >&2; exit 2 ;;
esac

udid=$(xcrun simctl list devices available --json | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for rt, devs in devices.items():
    if '.$runtime-' not in rt.replace('SimRuntime', ''):
        continue
    for d in devs:
        if d['name'].startswith('$family'):
            print(d['udid']); sys.exit()
")
if [ -z "$udid" ]; then
  echo "No available $family simulator for $runtime" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

echo "Testing on $runtime simulator $udid"
xcodebuild test \
  -scheme SkinKit-Package \
  -destination "id=$udid" \
  -skipPackagePluginValidation \
  > /tmp/skinkit-build.log 2>&1
rc=$?
grep -E "error:|warning: unre" /tmp/skinkit-build.log | sort -u | head -60
tail -n 40 /tmp/skinkit-build.log
exit $rc
