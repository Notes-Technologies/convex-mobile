# Universal macOS build

This fork adds Intel macOS support to the Rust core used by Convex Swift 0.8.2.
The starting point is upstream `f1a074ac2a4581f6f10f274eb237de05bbc91092`, whose
`ios` submodule points to Swift 0.8.2 (`1c69cdd9723ffb5857f48aa360d079ed09d614fd`).
The client implementation and Cargo.lock stay upstream; the fork adds a build
script and pins its Rust toolchain.

On a Mac with Xcode, CMake, Python 3, and rustup installed:

```sh
git clone --branch koori-universal-macos --recurse-submodules https://github.com/Notes-Technologies/convex-mobile.git
cd convex-mobile/rust
bash build-macos.sh
```

The toolchain file installs Rust 1.99.1 and both macOS targets. The script builds
with Cargo.lock and macOS 14 as the deployment target, verifies the generated
Swift bindings against the pinned Swift source, and combines the Intel and Apple
silicon libraries. The pinned upstream iOS device and simulator slices are kept.

Outputs are in `rust/target/koori-sdk`: the XCFramework, its SwiftPM ZIP and
checksum, and `build-info.json` recording source revisions and tool versions.
The [Swift fork](https://github.com/Notes-Technologies/convex-swift) consumes the
ZIP as a checksum-pinned release asset; no generated binaries are committed here.

To update upstream, update the Rust source and matching Swift submodule together,
rebuild, validate both architectures in Koori, then publish a new version and
checksum in the Swift fork. Do not overwrite an existing release asset.
