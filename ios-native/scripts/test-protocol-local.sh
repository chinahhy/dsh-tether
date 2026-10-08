#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build="$root/ProtocolKit/.build/local-smoke"
mkdir -p "$build/cache"
export CLANG_MODULE_CACHE_PATH="$build/cache/clang"
export SWIFT_MODULECACHE_PATH="$build/cache/swift"
swiftc -parse-as-library -module-cache-path "$build/cache/swift" \
  "$root/ProtocolKit/Sources/DSHMobileProtocol/Wire.swift" \
  "$root/ProtocolKit/Sources/DSHMobileProtocol/GatewayRPC.swift" \
  "$root/ProtocolKit/Smoke/main.swift" \
  -o "$build/protocol-smoke"
"$build/protocol-smoke"
