#!/usr/bin/env bash
# Build static XCFrameworks of every SkinKit module, and of ZIPFoundation, for a release.
#
#   scripts/build-xcframeworks.sh <version> [platform...]
#
# Platforms: ios ios-sim tvos tvos-sim catalyst (default: all five). Writes to dist/:
#   <Module>-<version>.xcframework.zip   one per module (SPM binaryTarget-ready)
#   SkinKit-Resources-<version>.zip      the modules' resource bundles
#   checksums.txt                        `swift package compute-checksum` of each zip
#
# Each module is its own static library (the target's .o, not its dependencies), so an app can link any
# set of them without duplicate symbols; link ZIPFoundation too. Built with library evolution, so the
# .swiftinterface files work with newer compilers. Each module declares a public enum of its own name
# (`SkinKitCore.version`), so interfaces name modules through aliases; otherwise `SkinKitCore.DeltaSkin` in an
# interface finds the enum, and compilers before Swift 6.3 reject it.
#
# Static libraries carry no resources. Apps add the bundles from the resources zip to their Copy Bundle
# Resources phase: SkinKitCore and SkinKitRetroArch find theirs (Bundle.module) at the top of the main bundle.
set -euo pipefail

version="${1:?usage: build-xcframeworks.sh <version> [ios ios-sim tvos tvos-sim catalyst]}"
shift
platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(ios ios-sim tvos tvos-sim catalyst)

modules=(SkinKitCore SkinCatalogKit SkinKitManager SkinKitUI SkinKitRetroArch ZIPFoundation)
bundles=(SkinKit_SkinKitCore SkinKit_SkinKitRetroArch ZIPFoundation_ZIPFoundation)

# PACKAGE_DIR builds another checkout (the release workflow builds a tag with this script from main).
root="$(cd "${PACKAGE_DIR:-$(dirname "$0")/..}" && pwd)"
cd "$root"
work="${WORK_DIR:-$root/.build/xcframeworks}"
dist="$root/dist"
rm -rf "$work" "$dist"
mkdir -p "$work" "$dist"

destination() {
  case "$1" in
    ios)      echo "generic/platform=iOS" ;;
    ios-sim)  echo "generic/platform=iOS Simulator" ;;
    tvos)     echo "generic/platform=tvOS" ;;
    tvos-sim) echo "generic/platform=tvOS Simulator" ;;
    catalyst) echo "generic/platform=macOS,variant=Mac Catalyst" ;;
    *) echo "unknown platform: $1" >&2; exit 2 ;;
  esac
}

products_dir() {
  case "$1" in
    ios)      echo "Release-iphoneos" ;;
    ios-sim)  echo "Release-iphonesimulator" ;;
    tvos)     echo "Release-appletvos" ;;
    tvos-sim) echo "Release-appletvsimulator" ;;
    catalyst) echo "Release-maccatalyst" ;;
  esac
}

# The xcframework's directory for a platform (ios-arm64, ios-arm64_x86_64-simulator, ...), read from its Info.plist.
slice_id() {
  python3 - "$1/Info.plist" "$2" <<'PY'
import plistlib, sys
platform, variant = {"ios": ("ios", None), "ios-sim": ("ios", "simulator"), "tvos": ("tvos", None),
                     "tvos-sim": ("tvos", "simulator"), "catalyst": ("ios", "maccatalyst")}[sys.argv[2]]
for library in plistlib.load(open(sys.argv[1], "rb"))["AvailableLibraries"]:
    if library["SupportedPlatform"] == platform and library.get("SupportedPlatformVariant") == variant:
        print(library["LibraryIdentifier"]); sys.exit()
sys.exit(f"no {sys.argv[2]} slice in {sys.argv[1]}")
PY
}

for platform in "${platforms[@]}"; do
  echo "== Building $platform"
  log="$work/build-$platform.log"
  if ! xcodebuild build \
    -scheme SkinKit-Package \
    -destination "$(destination "$platform")" \
    -configuration Release \
    -derivedDataPath "$work/derived" \
    -skipPackagePluginValidation \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    CLANG_COVERAGE_MAPPING=NO \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -alias-module-names-in-module-interface' \
    SKIP_INSTALL=NO \
    >"$log" 2>&1; then
    grep -E "error:" "$log" | head -20 >&2 || tail -40 "$log" >&2
    echo "build failed for $platform (log: $log)" >&2
    exit 1
  fi

  products="$work/derived/Build/Products/$(products_dir "$platform")"
  for module in "${modules[@]}"; do
    slice="$work/slices/$platform/$module"
    mkdir -p "$slice"
    libtool -static -o "$slice/lib$module.a" "$products/$module.o" 2>/dev/null
    # The package scheme gathers coverage; a release library must not carry its profiling hooks.
    if nm "$slice/lib$module.a" 2>/dev/null | grep -c llvm_profile >/dev/null; then
      echo "$module ($platform) is built with coverage instrumentation" >&2; exit 1
    fi
    # Ship the public interface only: no binary .swiftmodule (tied to one compiler), no private or package interface.
    rsync -a --exclude '*.swiftmodule' --exclude '*.private.swiftinterface' --exclude '*.package.swiftinterface' \
      "$products/$module.swiftmodule/" "$slice/$module.swiftmodule/"
  done
  if [ ! -d "$work/bundles" ]; then
    mkdir -p "$work/bundles"
    for bundle in "${bundles[@]}"; do cp -R "$products/$bundle.bundle" "$work/bundles/"; done
  fi
done

for module in "${modules[@]}"; do
  echo "== $module.xcframework"
  args=()
  for platform in "${platforms[@]}"; do args+=(-library "$work/slices/$platform/$module/lib$module.a"); done
  xcodebuild -create-xcframework "${args[@]}" -output "$work/out/$module.xcframework" >/dev/null
  # create-xcframework copies the library only; the module interface goes beside it in each slice.
  for platform in "${platforms[@]}"; do
    slice_dir=$(slice_id "$work/out/$module.xcframework" "$platform")
    cp -R "$work/slices/$platform/$module/$module.swiftmodule" "$work/out/$module.xcframework/$slice_dir/"
  done
  (cd "$work/out" && ditto -c -k --sequesterRsrc --keepParent "$module.xcframework" "$dist/$module-$version.xcframework.zip")
done

(cd "$work/bundles" && ditto -c -k --sequesterRsrc . "$dist/SkinKit-Resources-$version.zip")

(cd "$dist" && for zip in *.zip; do
  printf '%s  %s\n' "$(swift package compute-checksum "$zip")" "$zip"
done > checksums.txt)

echo "== dist/"
ls -l "$dist"
