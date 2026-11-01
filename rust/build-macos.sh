#!/usr/bin/env bash
# Build a universal macOS core while preserving the pinned upstream iOS slices.
set -euo pipefail

cd "$(dirname "$0")"
source_root="$(git rev-parse --show-toplevel)"
swift_root="$source_root/ios"
output="$PWD/target/koori-sdk"
staging="$output/headers"
framework="$output/libconvexmobile-rs.xcframework"
archive="$output/libconvexmobile-rs.xcframework.zip"

if [[ ! -f "$swift_root/Package.swift" ]]; then
  echo 'Initialize the pinned Swift submodule: git submodule update --init ios' >&2
  exit 1
fi

# Apply the same minimum OS to Rust and its C/C++ dependencies on both targets.
export MACOSX_DEPLOYMENT_TARGET=14.0
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

cargo build --locked --lib --release --target aarch64-apple-darwin
cargo build --locked --lib --release --target x86_64-apple-darwin

mkdir -p "$staging" "$output/macos"
cargo run --locked --release --target "$(rustc -vV | sed -n 's/^host: //p')" \
  --features=uniffi/cli --bin uniffi-bindgen -- generate \
  --library target/aarch64-apple-darwin/release/libconvexmobile.dylib \
  --language swift --no-format --out-dir "$staging"

# Never pair a new Rust ABI with stale generated Swift bindings.
cmp "$staging/convexmobile.swift" "$swift_root/Sources/UniFFI/convexmobile.swift"
rm "$staging/convexmobile.swift"
mv "$staging/convexmobileFFI.modulemap" "$staging/module.modulemap"

lipo -create target/aarch64-apple-darwin/release/libconvexmobile.a \
  target/x86_64-apple-darwin/release/libconvexmobile.a \
  -output "$output/macos/libconvexmobile.a"
for architecture in arm64 x86_64; do
  lipo "$output/macos/libconvexmobile.a" -verify_arch "$architecture"
done

rm -rf "$framework"
xcodebuild -create-xcframework \
  -library "$swift_root/libconvexmobile-rs.xcframework/ios-arm64/libconvexmobile.a" \
  -headers "$swift_root/libconvexmobile-rs.xcframework/ios-arm64/Headers" \
  -library "$swift_root/libconvexmobile-rs.xcframework/ios-arm64-simulator/libconvexmobile.a" \
  -headers "$swift_root/libconvexmobile-rs.xcframework/ios-arm64-simulator/Headers" \
  -library "$output/macos/libconvexmobile.a" -headers "$staging" \
  -output "$framework"

rm -f "$archive"
(cd "$output" && zip -X -q -r "$(basename "$archive")" "$(basename "$framework")")
swift package compute-checksum "$archive" > "$output/checksum.txt"

python3 - "$source_root" "$swift_root" "$archive" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

source, swift, archive = map(pathlib.Path, sys.argv[1:])
def command(*args):
    return subprocess.check_output(args, text=True).strip()

provenance = {
    "sourceRepository": "https://github.com/Notes-Technologies/convex-mobile",
    "sourceRevision": command("git", "-C", str(source), "rev-parse", "HEAD"),
    "swiftUpstreamRevision": command("git", "-C", str(swift), "rev-parse", "HEAD"),
    "cargoLockSHA256": hashlib.sha256((source / "rust/Cargo.lock").read_bytes()).hexdigest(),
    "rustc": command("rustc", "--version"),
    "xcode": command("xcodebuild", "-version"),
    "macOSDeploymentTarget": "14.0",
    "macOSArchitectures": ["arm64", "x86_64"],
    "archiveSHA256": hashlib.sha256(archive.read_bytes()).hexdigest(),
}
(archive.parent / "build-info.json").write_text(json.dumps(provenance, indent=2) + "\n")
PY

printf '\nSDK archive: %s\nChecksum: %s\n' "$archive" "$(cat "$output/checksum.txt")"
