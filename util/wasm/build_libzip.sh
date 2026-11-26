#!/bin/bash -e
# Builds libzip for Emscripten and installs it into the Emscripten sysroot,
# next to the other web dependencies (freetype, vorbis, ...), so that
# find_package(Libzip) in src/CMakeLists.txt succeeds for the web build.
#
# Required since the engine's client reads zip archives via libzip.
#
# Usage: source /path/to/emsdk/emsdk_env.sh && util/wasm/build_libzip.sh [version]

version=${1:-1.11.4}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

command -v emcmake >/dev/null || { echo "Activate emsdk first (emsdk_env.sh)" >&2; exit 1; }
sysroot=$(em-config CACHE)/sysroot

# zlib comes from the Emscripten port
embuilder build zlib

curl -fsSL "https://libzip.org/download/libzip-$version.tar.gz" -o "$work/libzip.tar.gz"
tar -xzf "$work/libzip.tar.gz" -C "$work"

emcmake cmake -S "$work/libzip-$version" -B "$work/build" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$sysroot" \
	-DBUILD_SHARED_LIBS=OFF \
	-DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF \
	-DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF \
	-DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
	-DENABLE_COMMONCRYPTO=OFF -DENABLE_GNUTLS=OFF \
	-DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
	-DZLIB_LIBRARY="$sysroot/lib/wasm32-emscripten/libz.a" \
	-DZLIB_INCLUDE_DIR="$sysroot/include"
cmake --build "$work/build" --parallel
cmake --install "$work/build"
